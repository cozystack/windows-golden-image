# windows-golden-image

Packer-based tooling to build a customized Windows Server golden image for [KubeVirt](https://kubevirt.io/) and [Cozystack](https://cozystack.io/). The image is built inside the cluster against the KubeVirt Packer builder, then captured as a reusable golden that can be cloned into new virtual machines.

## Repository layout

- [`images/workspace/`](./images/workspace/) — the Packer build project: build definition, variables, Windows answer files, provisioning scripts, and the DataVolume manifest for the source ISO. See [`images/workspace/README.md`](./images/workspace/README.md) for prerequisites and the exact build commands.
- [`docs/`](./docs/) — narrative documentation, including [`docs/workspace-image.md`](./docs/workspace-image.md) which explains what the image contains and how to register it in Cozystack.

## Getting started

Start with [`images/workspace/README.md`](./images/workspace/README.md). It covers the required tooling (Packer plus the KubeVirt builder plugin), the `KUBECONFIG` and namespace access the build needs, staging the source ISO as a DataVolume, and running the build. For the higher-level picture of what the image is for and how to make it reusable in Cozystack, read [`docs/workspace-image.md`](./docs/workspace-image.md).

## Secrets

No credentials, licences, or other secrets are baked into the image or committed to this repository. Build-time passwords are throwaway placeholders that you replace before building, and any real sign-in is done by hand in the running VM. See [`images/workspace/README.md`](./images/workspace/README.md) for details.

## License

Licensed under the [Apache License, Version 2.0](./LICENSE).
