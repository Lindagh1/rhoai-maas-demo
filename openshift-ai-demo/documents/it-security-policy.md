# Acme Corp — IT Security Baseline Policy

**Document ID:** IT-POL-002
**Owner:** Information Security Team
**Last reviewed:** January 2026

## Purpose

This document defines the minimum security controls required on any device
used to access Acme Corp systems, whether on-site or remote.

## Device requirements

- Full-disk encryption must be enabled on laptops and desktops.
- Endpoint protection (EDR agent) must report a healthy status within the
  last 24 hours before VPN access is granted.
- Screen lock must trigger automatically after 5 minutes of inactivity.

## Access control

- Multi-factor authentication (MFA) is mandatory for all corporate
  applications, including email, VPN, and the HR portal.
- Password rotation is required every 180 days for standard accounts and
  every 90 days for administrative accounts.
- Shared accounts are prohibited; every employee must use individually
  attributable credentials.

## Remote access

Remote workers — including those using the Monday/Friday remote work
allowance described in the HR Remote Work Policy — must connect through the
corporate VPN before accessing internal tools such as Jira, Confluence, or
the internal model catalog. Split-tunnel VPN configurations are not
permitted for any device holding production credentials.

## Incident reporting

Any suspected phishing email, lost device, or credential compromise must be
reported to security@acme-corp.example within one hour of discovery via the
#security-incidents Slack channel or the 24/7 hotline.

## Data classification

Documents are classified as Public, Internal, Confidential, or Restricted.
This policy and the HR Remote Work Policy are classified **Internal** and
may be shared with all employees and approved contractors.
