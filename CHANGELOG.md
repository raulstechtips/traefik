# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add a ClusterRole that aggregates to `admin`, so namespace admins such as `jenkins-deployer` can manage namespaced Traefik resources ([SWEALTH-329](https://raulstechtips.atlassian.net/browse/SWEALTH-329)).

### Changed

### Fixed

- Unauthenticated requests on `oauth-chain` routes now get a `302` to Keycloak, and after login the browser goes back to the original app URL. Before, the browser showed a blank "Found" page and stayed on oauth2-proxy after login. `oauth-verify` now calls the oauth2-proxy root. The `oauth-signin` Middleware and the `middlewares.oauth.signIn` values are removed; prune `default/oauth-signin` on the next sync ([DEVSECOPS-200](https://raulstechtips.atlassian.net/browse/DEVSECOPS-200)).

## [0.1.0] - 2026-11-08

[Unreleased]: https://github.com/raulstechtips/traefik/compare/0.1.0...HEAD
[0.1.0]: https://github.com/raulstechtips/traefik/releases/tag/0.1.0
