## Summary

Describe the purpose of this pull request and the problem it solves.

## Changes

-
-
-

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Security improvement
- [ ] Installer or updater change
- [ ] Routing, DNS, nftables, or systemd change
- [ ] Refactoring
- [ ] Release preparation

## Validation performed

- [ ] `ruff check .`
- [ ] `pytest`
- [ ] Bash syntax validation passed
- [ ] ShellCheck passed
- [ ] nftables rules validated with `nft -c`
- [ ] systemd units validated with `systemd-analyze verify`
- [ ] Non-disruptive smoke test passed
- [ ] Full failover smoke test passed, when applicable

```bash
ruff check .
pytest
bash -n gateway.sh install.sh update.sh uninstall.sh installer-lib.sh scripts/smoke-test.sh
shellcheck -x gateway.sh install.sh update.sh uninstall.sh scripts/smoke-test.sh
sudo bash scripts/smoke-test.sh
sudo bash scripts/smoke-test.sh --with-failover
```

## Fail-closed and security impact

- [ ] Managed devices cannot silently fall back to the normal LAN router.
- [ ] The blackhole default route remains present.
- [ ] DNS remains protected through the VPN routing table.
- [ ] No unintended LAN access or unnecessary privilege was introduced.
- [ ] Sensitive runtime information is not included in the change.

Explain any routing, DNS, firewall, privilege, or security impact:

```text

```

## Upgrade and rollback

- [ ] Existing installations remain supported.
- [ ] Installer and updater changes were made when required.
- [ ] New managed files are included in backup and rollback handling.
- [ ] Uninstall behavior was reviewed.
- [ ] Configuration migration was tested when applicable.

## Documentation

- [ ] English documentation was updated.
- [ ] Greek documentation was updated when applicable.
- [ ] Wiki or technical documentation was updated.
- [ ] `CHANGELOG.md` was updated.
- [ ] Version metadata was updated when applicable.

## Screenshots

Add screenshots for visible web-panel changes.

## Related issues

Closes #

## Final checklist

- [ ] The change is focused and contains no unrelated modifications.
- [ ] Tests were added or updated.
- [ ] CI passes.
- [ ] Fail-closed behavior is preserved.
- [ ] Backward compatibility was considered.
- [ ] I reviewed the final diff.
