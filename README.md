# SDCA deployment

This repo deploys the SDCA website.

It uses cloud-init.


To create a VM using Multipass, with name sdca, run:

```
multipass launch -n sdca --cloud-init cloud-config.yaml 20.04
```
