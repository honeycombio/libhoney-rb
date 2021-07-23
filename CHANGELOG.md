# libhoney-rb changelog

## changes pending release

## 1.19.0

### Improvements

- add a test_helper, Minitest reporters, & store test results in CI (#88)
- add experimental transmission with new sized-and-timed queue (#87)

### Fixes

- Process single-error responses from the Batch API (#89)

## 1.18.0

### Improvements

- replace HTTP client library to reduce external dependencies (#81)

### Deprecations

- `Libhoney::Client.new(proxy_config: _)`: the `proxy_config` parameter for client
  creation will no longer accept an Array in the next major version. The recommended
  way to configure the client for operation behind forwarding web proxies is to set
  http/https/no_proxy environment variables appropriately.

## 1.17.0

### Fixes:

- Allow Ruby 3.0.0 (removes overly-pessimistic exception) (#79)

## 1.16.1

### Fixes:

- Fix closing down the client when no threads have been started. (#74 & #76)

## 1.16.0

### Fixes:

- Don't moneypatch Class (#70)

### Maintenance:

- Add lockfile to gitignore (#71)

## 1.15.0

### Improvements:

- Do not attempt to send invalid events (#67)

### Maintenance:

- Modernize circle, include github publishing (#64)
- Update .editorconfig to add new lines to end of files (#68)

### Misc

-   Added CHANGELOG.md
-   Updates to CI configuration and documentation
-   Updated version management.
