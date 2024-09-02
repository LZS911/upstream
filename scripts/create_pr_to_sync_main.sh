check_pr_status() {
  local pr_number=$1
  local max_attempts=$2
  local wait_time=$3
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    local merge_status=$(gh pr view $pr_number --json mergeable -q '.mergeable')

    if [ "$merge_status" != "UNKNOWN" ]; then
      echo $merge_status
      return 0
    fi

    sleep $wait_time
    ((attempt++))
  done

  echo "TIMEOUT"
  return 1
}
create_and_close_conflicting_pr() {
  local pr_number=$1
  # 创建新分支
  new_branch="sync-main-to-main-ee-$(date +%Y%m%d%H%M%S)"
  git checkout main
  git checkout -b $new_branch
  git push origin $new_branch

  # 创建新的 PR
  new_pr=$(gh pr create --base main-ee --head $new_branch \
    --title "Sync main to main-ee (resolved conflicts)" \
    --body "Automatically created PR to sync changes from main to main-ee. This PR was created to resolve conflicts.")

  # 关闭旧的 PR
  gh pr close $pr_number --comment "Closing due to conflicts. New PR created: $new_pr"
  return 0
}
set -e
trap 'echo "Error occurred. Exiting..."; exit 1' ERR # 捕获错误并退出

# 检查是否已经存在从 main 到 main-ee 的 PR
existing_pr=$(gh pr list --base main-ee --head main --json number --jq '.[0].number')

if [ -z "$existing_pr" ]; then
  # 创建新的 PR
  new_pr=$(gh pr create --base main-ee --head main \
    --title "Sync main to main-ee" \
    --body "Automatically created PR to sync changes from main to main-ee")

  # 检查 PR 是否成功创建
  if [ $? -ne 0 ]; then
    echo "Failed to create PR"
    exit 1
  fi

  # 从 PR URL 中提取 PR 编号
  pr_number=$(echo "$new_pr" | grep -oE '[0-9]+$')

  # 检查是否成功获取 PR 编号
  if [ -z "$pr_number" ]; then
    echo "Failed to extract PR number from: $new_pr"
    exit 1
  else
    echo "Created new PR #$pr_number"
    echo "PR URL: $new_pr"
  fi

  # 检查新创建的 PR 是否有冲突
  merge_status=$(check_pr_status $pr_number 10 10)
  echo "merge_status value: '$merge_status'"

  if [ "$merge_status" = "CONFLICTING" ]; then
    create_and_close_conflicting_pr $pr_number || exit 1
  else
    echo "Created new PR #$pr_number without conflicts."
  fi

else
  echo "A PR from main to main-ee already exists (PR #$existing_pr). Checking for conflicts..."

  # 检查是否有冲突
  merge_status=$(check_pr_status $existing_pr 10 10)
  echo "merge_status value: '$merge_status'"

  if [ "$merge_status" = "CONFLICTING" ]; then
    echo "Conflicts detected. Creating new branch and PR..."

    create_and_close_conflicting_pr $existing_pr || exit 1

  else
    echo "Existing PR has no conflicts."
  fi
fi
