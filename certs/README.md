# MAR verification certificates

Only public DER certificates belong in this directory. Private keys and NSS
databases must remain outside Git.

`nightsedge-mar-primary.der` has this SHA-256 fingerprint:

```text
5E:CC:3E:18:BD:B6:3F:4D:39:59:99:90:FA:B3:BD:BA:A4:EF:4E:70:A6:2A:50:E2:3C:6B:81:92:A5:2F:45:40
```

Until `nightsedge-mar-secondary.der` is added, builds use the primary
certificate in both of Firefox's MAR verification slots.
