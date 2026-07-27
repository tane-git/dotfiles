---
name: jira-images
description: Download and view image attachments from Rocket Lab Jira issues
---

## When to use

When Jira issue has image attachments you need to see (e.g., `!filename.png!` in description).

## Steps

**Get attachment URLs:**
```bash
curl -s -H "Authorization: Bearer ${JIRA_PAT}" \
  "https://jira.rocketlab.local/rest/api/2/issue/<ISSUE-KEY>" \
  | jq -r '.fields.attachment[] | .content'
```

**Download:**
```bash
curl -s -H "Authorization: Bearer ${JIRA_PAT}" \
  "<ATTACHMENT_URL>" -o "/tmp/<descriptive-name>.png"
```

**View:**
```
Read { filePath: "/tmp/<descriptive-name>.png" }
```
