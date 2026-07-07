# Contributing

1. Fork the repository and create a focused branch.
2. Keep runtime secrets and local configuration out of commits.
3. Run the local checks before opening a pull request:

```bash
python3 -m py_compile app.py
bash -n gateway.sh install.sh update.sh uninstall.sh
```

4. Describe the networking assumptions and test environment in the pull request.
5. Preserve fail-closed behavior for managed devices.
