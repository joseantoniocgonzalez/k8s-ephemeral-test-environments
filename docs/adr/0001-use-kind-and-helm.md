# ADR 0001: Use kind and Helm for ephemeral test environments

## Status

Accepted

## Context

The project needs to create short-lived Kubernetes environments locally and in GitHub Actions without depending on a permanent cluster or a paid cloud provider.

## Decision

Use kind to create disposable Kubernetes clusters on top of Docker and Helm to package and deploy the IOC Reputation Checker API and PostgreSQL.

The MVP will not include Terraform, Ansible, OpenShift, Argo CD, Flux, or a public cloud provider.

## Consequences

- The environment can be reproduced locally and in CI.
- The project has no cloud infrastructure cost.
- Cluster creation and deletion can be automated.
- The first version remains focused on Kubernetes, deployment validation, and testing.
- Cloud provisioning and GitOps may be evaluated only after the MVP is complete.
