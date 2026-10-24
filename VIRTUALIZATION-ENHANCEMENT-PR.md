# Plan: add container, orchestrator and cloud detection to the `virtualization` resource

Status: plan, 2026-10-24. Replaces the first-draft description of commit `52e30ce79`
(`al/virtualization-enhancement`). Review of that draft: `VIRTUALIZATION-REVIEW.md`.

## Goal

Profiles need to know the whole stack a target runs on: the hypervisor, whether it is a container,
which orchestrator runs it, and which cloud hosts it. The `virtualization` resource reports a single
`system` and `role` today. This change adds the other layers **without changing any answer the resource
gives today**.

## What the first draft got wrong

The first draft replaced `main`'s detection code instead of adding to it. That removed `openstack`, the
systemd cgroup patterns, `kubepods` and `params`, changed the `resource_id` fallback, and reordered
detection so that Kubernetes, container and cloud checks override hypervisor answers. Its description
said "Breaking Changes: None"; the review found twelve. Details, evidence and the 37-scenario comparison:
`VIRTUALIZATION-REVIEW.md` §1-2.

Its data model was the right idea: separate fields for each layer and matchers such as
`be_kubernetes`. The fault was detecting every layer in one first-match-wins chain, run eagerly on every
scan.

## Design

### 1. Existing API: unchanged

`main`'s detection chain (`lib/inspec/resources/virtualization.rb` at InSpec 7.3.4) stays as it is:
same checks, same order, same values.

| API | Values |
|---|---|
| `system`, `role` | Linux: `xen`, `docker`, `vbox`, `lxd`, `lxc`, `kubepods`, `podman`, `linux-vserver`, `kvm`, `openvz`, `openstack`, `parallels`, `vmware`, `hyper-v`. Windows: `hyper-v`, `vmware`, `virtualbox` |
| `resource_id` | Detected `system`, or `"virtualization"` |
| `physical_system?`, `virtual_system?`, `params`, `to_s` | Unchanged |

One declared bug fix: on Windows, `main` reads the WMI JSON with a symbol key
(`windows_computer_system[:manufacturer]`), so the Xen and QEMU branches never run. The docs already list
`xen` and `kvm` for Windows. The fix uses the `"Manufacturer"` key; the PR description declares it as a
behaviour change.

### 2. New layers: independent and lazy

Each layer is its own method, evaluated on first use and memoized. No layer writes `system` or `role`,
and no layer can stop another. A profile that only reads `system` runs exactly the commands it runs
today.

| Layer | API | Answers | Signals |
|---|---|---|---|
| Hypervisor | `hypervisor` | The VM layer under the target, even when `system` is a container (`docker` on KVM gives `hypervisor "kvm"`) | `main`'s own checks: DMI, cpuinfo `hypervisor` flag, `/proc/xen`, kernel modules |
| Container | `container?`, `container_runtime` | Running in a container; runtime `docker`, `podman`, `containerd`, `cri-o`, `lxc` or `lxd` | Container-side only: `/.dockerenv`, `/run/.containerenv`, cgroup paths, `container=` in `/proc/1/environ` |
| Orchestrator (workload) | `kubernetes?`, `orchestrator`, `k8s_namespace`, `k8s_pod_name` | Running in a Kubernetes pod, Nomad allocation or ECS task, with namespace and pod name | Service-account token and namespace file, `kubepods` cgroup, `NOMAD_*` and `ECS_CONTAINER_METADATA_URI` in `/proc/1/environ` |
| Orchestrator (node) | `kubernetes_node?` | The target is a Kubernetes node | `/var/lib/kubelet`, `/etc/kubernetes` |
| Kubernetes distribution | `k8s_distribution` | `eks`, `gke`, `aks`, `openshift`, `k3s`, `kind`, `minikube`, ... only where a reliable signal exists; otherwise `"kubernetes"` | Research first (open question 2) |
| Cloud | `cloud_provider`, `cloud?`, `aws?`, `gcp?`, `azure?` | `aws-ec2`, `gcp-gce`, `azure-vm`, `digitalocean`; serverless `ecs-fargate`, `cloud-run`, `azure-aci`. Fargate counts as `aws?` | DMI first (vendor, product UUID, Azure chassis asset tag). Metadata endpoints only when DMI already indicates that cloud |
| Summary | `metadata` | Frozen hash of every layer | |

Example: a pod on EKS on a Nitro instance reports `system "kubepods"`, `role "guest"` (unchanged),
`container_runtime "containerd"`, `orchestrator "kubernetes"`, `k8s_namespace "prod"`, and, if the pod can
read DMI (open question 3), `hypervisor "kvm"` and `cloud_provider "aws-ec2"`.

### 3. Rules for every detector

- Pod and container detection uses only signals visible inside the workload. Host paths, `pgrep` and
  `which <tool>` are never evidence of being a guest.
- Every network call has `--connect-timeout` and `--max-time`. Remote data is validated by shape and never
  interpolated into a shell command.
- Local tools (kind, minikube, Docker Desktop, OrbStack, Colima) are `k8s_distribution` values or are not
  reported. They are never a `cloud_provider`.
- A value the code cannot back is not exposed. No `confidence`, `detection_method` or `detection_time`.

### 4. Not carried over from the first draft

| Item | Reason |
|---|---|
| `confidence`, `detection_method`, `detection_time` | Values not backed by the code; no accessors |
| Docker Swarm, Docker Compose | No reliable signal from inside a container |
| `utm` | Unreachable on Linux; macOS detection would be a separate change |
| `virtual_machine?`, `virtual_host?`, `virtual_guest?`, `physical?`, `kind?` | Duplicate existing matchers or fold into `k8s_distribution`; not needed for the goal |

## Tests

InSpec's unit-test style: `MockLoader` on Train's mock transport, where unmocked files are absent and
unmocked commands exit 1. The existing test's inverted file mock (unlisted files "exist") is replaced by
an absent-by-default helper.

1. **Regression tests against unmodified `main` first.** `VIRTUALIZATION-REVIEW.md` §6 items 1-22:
   nothing detected, every Linux container and hypervisor branch, the vbox-before-kvm order, OpenStack,
   Windows, and mixed-signal hosts. Each asserts `system`, `role`, `resource_id`, `physical_system?` and
   `virtual_system?` exactly. All pass on `main` before any production change. A later change that turns
   one red is a breaking change.
2. **One test file section per new layer**, each with exact expected values (review §6 items 23-30, revised
   for the layer design): the pod, node, kind, EC2, Azure and Fargate scenarios; `physical_system?` never
   true while a cloud or orchestrator is set; no network command when only `system` is read; every `curl`
   has timeouts; a token containing `$(...)` never reaches a shell unquoted.
3. `virtualization-review-harness.rb` is the scenario list to start from. It is not part of the PR.

## Order of work

1. Branch from `main`; replace the inverted test mock; pin the "nothing detected" contract.
2. Regression tests for Linux containers, Linux hypervisors, OpenStack, Windows and mixed-signal hosts
   (test-only; green on unmodified `main`).
3. Windows `Manufacturer` key fix (test first).
4. Hypervisor layer: extract `main`'s checks into query helpers shared by the legacy chain and the
   `hypervisor` layer; the regression tests prove the chain is unchanged.
5. Container layer.
6. Orchestrator workload layer (Kubernetes, Nomad, ECS).
7. Kubernetes node matcher.
8. Research, then `k8s_distribution`.
9. Research, then the cloud layer (DMI first, guarded metadata calls, serverless).
10. `metadata`.
11. Docs: `docs-chef-io/content/inspec/resources/virtualization.md` lists every new property and matcher
    with its values, and states that `system`/`role` precedence is unchanged.
12. Live checks on the environments available (Docker, Podman, OrbStack Kubernetes, a cloud VM if
    available), output recorded on the card.
13. Upstream PR: `chefstyle` clean, every commit signed off for the DCO (`git commit -s`, InSpec
    `CONTRIBUTING.md`), this file, the review, the harness, `test-virtualization.rb` and
    `virtualization-enhancement.zip` removed from the branch, PR description written from this plan.
    `CHANGELOG.md` is generated at merge and is not edited.

## Open questions

1. **WMI failure on Windows.** `main` raises `NoMethodError`, which InSpec reports as a skipped resource.
   Keep that, or raise `Inspec::Exceptions::ResourceSkipped` with a clear message (same result, readable
   reason)? Either way, never report `physical_system? true` for a failed probe.
2. **Kubernetes distribution signals.** Which distributions have a reliable signal from inside a pod?
   Candidates to verify: OpenShift's service-account `service-ca.crt`, the API server host in
   `KUBERNETES_SERVICE_HOST` combined with the cloud layer, node-name patterns. Distributions without one
   report `"kubernetes"`.
3. **DMI inside containers.** Whether `/sys/class/dmi/id` is readable in a pod decides whether the
   hypervisor and cloud layers work from inside containers or only on hosts.
4. **Unverified items from the review:** the `lxd` snap on Ubuntu Server images; Compose environment
   variables; metadata-server error bodies; timeout behaviour on blocked link-local routes.

## References

Line numbers are at InSpec 7.3.4 (`main` at `2183c4506`) and train-core 3.16.5. Re-check them if
`main` moves.

### Code to port from

- First draft: branch `al/virtualization-enhancement`, commit `52e30ce79` (on `origin`, reference only,
  never opened as a PR). `VIRTUALIZATION-REVIEW.md` cites it as `wip:virt.rb:N`. Port a detector only
  after the review finding for it is addressed.
- Current resource: `lib/inspec/resources/virtualization.rb`. Detection chain `collect_data_linux`
  (order: xen, docker, virtualbox, lxd, container, linux-vserver, kvm from cpuinfo, kvm from sys,
  openvz, openstack, parallels, vmware, hyper-v); Windows `collect_data_windows` and
  `windows_computer_system` (called twice; the `[:manufacturer]` symbol-key bug).

### InSpec resource lifecycle and errors

- `lib/inspec/exceptions.rb:8-9`: `Inspec::Exceptions::ResourceFailed`, `ResourceSkipped`.
- `lib/inspec/resource.rb:47-69`: `supersuper_initialize` wraps only the resource's `initialize`.
  `ResourceSkipped` → skipped (`:61`), `ResourceFailed` → failed (`:63`), `NoMethodError` → skipped
  (`:67`). An exception raised later, inside a property read in an `its` block, is a plain test error.
- `lib/inspec/resource.rb:71-82`: `check_supported!` raises `ArgumentError` ("Unsupported
  resource/backend combination") off-platform, except on Train's mock backend (`:76`).
- `lib/inspec/runner.rb:349-366`: the runner reports a skipped resource before a failed one.
- `lib/inspec/utils/filter.rb:7` (`ExceptionCatcher`), `:423`: FilterTable methods catch both
  exceptions.
- `lib/inspec/utils/file_reader.rb:10-19`: core's precedent: a missing, unreadable or empty source is
  `ResourceSkipped`.
- `lib/inspec/resources/command.rb:75-94`: `command(...).exist?` is false only when the OS name is nil
  or `"mock"`; on Linux it runs `sh -c 'type "<cmd>"'` (`which` on Alpine), on Windows `Get-Command`.

### Conventions

- `resource_id` fallback is the resource's own name: `platform.rb:97` (`|| "platform"`), `os.rb:31`
  (`|| "OS"`), `sys_info.rb:116`. It is emitted in JSON results (`lib/inspec/reporters/json.rb:50-60`).
- `docs-chef-io/content/inspec/profiles/custom_resources.md`: custom resource API, `resource_id`,
  raising `ResourceSkipped`.
- `docs-chef-io/content/inspec/resources/virtualization.md`: the public contract: `system` names
  (§"virtualization.system names"), `virtual_system?` and `physical_system?` (§Matchers).
- `dev-docs/filtertable-internals.md`: FilterTable behaviour, if a layer ever exposes a table.

### Unit-test helpers

- `test/helpers/mock_loader.rb:47` `MockLoader.new(os)`; OS table at `:3` (`ubuntu` `:23`, `windows`
  `:26`); `load_resource` `:743`; `MockLoader.mock_command` `:757`.
- Command-existence mocks in InSpec's own table: `mock_loader.rb:225-229`
  (`'sh -c \'type "pip"\'' => empty.call`).
- Train mock (`train-core/lib/train/transports/mock.rb`): `mock_command` `:108`; unmocked command exits 1
  (`command_not_found` `:112-119`); unmocked file does not exist (`File#initialize`, `@exist = false`
  `:175`); lookup `run_command_via_connection` `:133` (keys by the SHA256 of the command; the raw string
  is found through Train's command cache, so set both or use `MockLoader.mock_command`).
- Existing tests: `test/unit/resources/virtualization_test.rb`. Scenario list:
  `virtualization-review-harness.rb` (run: `bundle exec ruby -Ilib -Itest virtualization-review-harness.rb`).

### Contributing and checks

- `CONTRIBUTING.md:49` and following: DCO, every commit signed off (`git commit -s`).
- `CONTRIBUTING.md:45`: `CHANGELOG.md` is generated at merge; do not edit it.
- `Rakefile:41-47`: `bundle exec rake test:lint` runs chefstyle (RuboCop); `bundle exec rake test:unit`
  runs the unit suite.

## Author

Aaron Lippold
