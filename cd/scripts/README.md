### Introduction

This directory contains mainly two scripts `release-controller.sh` and 
`auto-generate-controller.sh` along with template files that provide the content
 for creating github issues and pull requests using ack-bot.


### Gotchas
* `gh_issue_body_template.txt` & `gh_pr_body_template.txt` provide the body
content for GitHub issue and PR creation from `auto-generate-controller.sh`
script. Mark down is supported from these files but be careful about the variable
expansion since these files are evaluated in bash shell.
  > NOTE: Add backslash(\\) before back-tick(`) and '$' symbol to preserve them
  > inside GitHub issue/PR body.
 



  