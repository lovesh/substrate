#!/bin/sh
#
# check for a polkadot companion pr and ensure it has approvals and is
# mergeable
#

github_api_substrate_pull_url="https://api.github.com/repos/paritytech/substrate/pulls"
github_api_polkadot_pull_url="https://api.github.com/repos/paritytech/polkadot/pulls"
# use github api v3 in order to access the data without authentication
github_header="Authorization: token ${GITHUB_PR_TOKEN}"

boldprint () { printf "|\n| \033[1m${@}\033[0m\n|\n" ; }
boldcat () { printf "|\n"; while read l; do printf "| \033[1m${l}\033[0m\n"; done; printf "|\n" ; }



boldcat <<-EOT


check_polkadot_companion_status
===============================

this job checks if there is a string in the description of the pr like

polkadot companion: paritytech/polkadot#567

or any other polkadot pr is mentioned in this pr's description and checks its
status.


EOT


if ! [ "${CI_COMMIT_REF_NAME}" -gt 0 2>/dev/null ]
then
  boldprint "this doesn't seem to be a pull request"
  exit 1
fi

boldprint "this is pull request no ${CI_COMMIT_REF_NAME}"

pr_body="$(curl -H "${github_header}" -s ${github_api_substrate_pull_url}/${CI_COMMIT_REF_NAME} \
  | sed -n -r 's/^[[:space:]]+"body": (".*")[^"]+$/\1/p')"

# get companion if explicitly specified
pr_companion="$(echo "${pr_body}" | sed -n -r \
    -e 's;^.*polkadot companion: paritytech/polkadot#([0-9]+).*$;\1;p' \
    -e 's;^.*polkadot companion: https://github.com/paritytech/polkadot/pull/([0-9]+).*$;\1;p' \
  | tail -n 1)"

# get companion mentioned in the description
if [ -z "${pr_companion}" ]
then
  pr_companion="$(echo "${pr_body}" | sed -n -r \
    's;^.*https://github.com/paritytech/polkadot/pull/([0-9]+).*$;\1;p' \
    | tail -n 1)"
fi

if [ -z "${pr_companion}" ]
then
  boldprint "no companion pr found"
  exit 0
fi

boldprint "companion pr: #${pr_companion}"

# check the status of that pull request - needs to be
# mergable and approved

curl -H "${github_header}" -sS -o companion_pr.json \
  ${github_api_polkadot_pull_url}/${pr_companion}

pr_head_sha=$(jq -r -e '.head.sha' < companion_pr.json)
boldprint "Polkadot PR's HEAD SHA: $pr_head_sha"

if jq -e .merged < companion_pr.json >/dev/null
then
  boldprint "polkadot pr #${pr_companion} already merged"
  exit 0
fi

if jq -e '.mergeable' < companion_pr.json >/dev/null
then
  boldprint "polkadot pr #${pr_companion} mergeable"
else
  boldprint "polkadot pr #${pr_companion} not mergeable"
  exit 1
fi

curl -H "${github_header}" -sS -o companion_pr_reviews.json \
  ${github_api_polkadot_pull_url}/${pr_companion}/reviews

# If there are any 'CHANGES_REQUESTED' reviews for the *current* review
while IFS= read -r line; do
  if [ "$line" = "$pr_head_sha" ]; then
    boldprint "polkadot pr #${pr_companion} has CHANGES_REQUESTED for the latest commit"
    exit 1
  fi
done <<< $(jq -r -e '.[] | select(.state == "CHANGES_REQUESTED").commit_id' < companion_pr_reviews.json)

# Then we check for at least 1 APPROVED
if [ -z "$(jq -r -e '.[].state | select(. == "APPROVED")' < companion_pr_reviews.json)" ]; then
  boldprint "polkadot pr #${pr_companion} not APPROVED"
  exit 1
fi

boldprint "polkadot pr #${pr_companion} state APPROVED"
exit 0


