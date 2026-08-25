# Security Policy

[Back to the project README](../readme.md).

EltenLink is social infrastructure used every day. Please report suspected vulnerabilities privately so that they can be investigated and corrected before details become public.

## Reporting a vulnerability

Send the report directly by email to:

- [dawidpieper@o2.pl](mailto:dawidpieper@o2.pl)
- [d.pieper@prowadnica.org](mailto:d.pieper@prowadnica.org)

Sending one message to both addresses is strongly encouraged, and placing the second address in CC is very welcome. This reduces the risk of a time-sensitive report being overlooked.

Use a clear subject such as `ELTEN SECURITY: short description`. If ordinary email is not suitable for the material you need to share, make initial contact without the sensitive attachment and agree on a safer transfer method.

Do not report an undisclosed vulnerability through GitHub, a public EltenLink forum, a beta-testing group, a blog or another public channel.

## What to include

A useful report contains as much of the following as is available:

- the affected Elten version or build identifier;
- the operating system and architecture;
- the affected component, endpoint or workflow;
- the type of vulnerability and its likely impact;
- reproducible steps or a minimal proof of concept;
- whether authentication, particular account rights or user interaction are required;
- relevant logs, stack traces, request identifiers;
- any suggested mitigation or fix;
- your preferred name and contact details for follow-up;
- any proposed disclosure date or other time constraint.

Remove unrelated credentials, session tokens, private messages and personal data. If a secret is essential to demonstrate the issue, say so first and arrange an appropriate way to provide it.

## Scope

Security reports may concern, among other areas:

- authentication, sessions and account boundaries;
- network transport, API requests and certificate handling;
- updater downloads and installer execution;
- launcher integrity and embedded assets;
- application or extension package validation;
- unsafe file handling, path traversal or command execution;
- exposure of credentials, private content or personal data;
- platform-specific native integrations.

This repository contains the desktop client, but the same email addresses may be used when a finding appears to involve the EltenLink service or when the affected component is unclear.

## Responsible testing

Please use your own accounts and test data wherever possible. Do not intentionally access another person's content, alter or delete data, degrade the service, send bulk traffic, install persistence, or extend testing beyond what is necessary to demonstrate the problem.

If testing could affect other users, production availability or data integrity, stop and ask for guidance by email before proceeding.

## Disclosure

Please allow a reasonable period for investigation and remediation before publishing technical details. Coordinate the timing and scope of disclosure through the email thread. A release candidate may change quickly, so confirm that a report still applies to the latest code before public discussion.

Ordinary defects without a security impact should be reported through the beta-testing groups described in the [contributing guide](contributing.md#planning-a-change).

Thank you for taking the time to report security issues responsibly and for helping to protect EltenLink, its users and the wider community.
