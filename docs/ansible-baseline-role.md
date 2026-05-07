# Ansible Baseline Role

This project includes a small Ansible role for creating more projects with the same uv + mkosi shape.

The role is deliberately simple. It is meant for stamping out local project baselines, not managing production systems.

## Why Ansible instead of a shell script?

Ansible is a good fit if you expect to repeat this setup several times because it gives you:

- idempotent tasks where possible
- named defaults in `defaults/main.yml`
- templates for generated config files
- a clean way to override project name, root, Debian release, and package lists
- a path toward reusing the baseline from another repository later

A shell script would be fine for a one-off. For repeated project creation, the Ansible role is easier to inspect and evolve.

## Files

```text
ansible/create-uv-mkosi-project.yml
ansible/example-vars.yml
ansible/roles/uv_mkosi_project_baseline/
```

## Create another project

From this repository:

```bash
cd /home/aok/Local/Projects/pe-uki-lab
ansible-playbook ansible/create-uv-mkosi-project.yml \
  -e project_name=another-uki-lab
```

Or use the example vars file:

```bash
ansible-playbook ansible/create-uv-mkosi-project.yml \
  -e @ansible/example-vars.yml
```

Then open it from Windows:

```powershell
code --remote wsl+Debian /home/aok/Local/Projects/another-uki-lab
```

## Build the generated project

```bash
cd /home/aok/Local/Projects/another-uki-lab
sudo mkosi -f build
```

## Notes

The role can install host packages and uv. It also writes the mkosi config and overlay files. By default it adds `ruff` and `pytest` as uv dev dependencies.

The `uv add --dev` task is intentionally simple. If you run the role repeatedly, uv should keep the dependency state stable, but this is still a project bootstrapper rather than a full dependency policy engine.
