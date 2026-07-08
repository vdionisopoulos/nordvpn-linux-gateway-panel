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

Commands:

```bash
ruff check .
pytest

bash -n \
  gateway.sh \
  install.sh \
  update.sh \
  uninstall.sh \
  installer-lib.sh \
  scripts/smoke-test.sh

shellcheck -x \
  gateway.sh \
  install.sh \
  update.sh \
  uninstall.sh \
  scripts/smoke-test.sh

sudo bash scripts/smoke-test.sh
sudo bash scripts/smoke-test.sh --with-failover
