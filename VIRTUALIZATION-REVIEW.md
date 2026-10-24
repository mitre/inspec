# Review: `virtualization` resource, `main` (7.3.4) vs `al/virtualization-enhancement` (52e30ce)

Independent read-only review, 2026-10-24. Compares the first-draft enhancement commit `52e30ce79`
on `al/virtualization-enhancement` with `main` at `2183c4506` (InSpec 7.3.4). The scenario harness it
used is saved next to this file as `virtualization-review-harness.rb` (run from the repo root with
`bundle exec ruby -Ilib -Itest virtualization-review-harness.rb`).

Hand-checked after the review: main's `kubepods` and systemd-cgroup patterns (`main:virt.rb:217-226`),
the first draft's cgroup patterns (`wip:virt.rb:795,813`), the EC2 fallback returning `true` without
setting `system` (`wip:virt.rb:944-952`), and `in_kubernetes_pod?` treating node paths as pod signals
(`wip:virt.rb:612-627`). All four are as stated.

One correction: where this review says "CHANGELOG entry", InSpec's `CONTRIBUTING.md:45` says
`CHANGELOG.md` is generated when a PR merges. Behaviour changes are declared in the PR description.

Notation: `main:virt.rb:N` = `main:lib/inspec/resources/virtualization.rb:N`; `wip:virt.rb:N` = same path on `al/virtualization-enhancement`; `PR.md` = `VIRTUALIZATION-ENHANCEMENT-PR.md` on the first-draft ref; `docs:N` = `docs-chef-io/content/inspec/resources/virtualization.md` (unchanged on the first draft, `git diff --stat main al/... -- docs-chef-io/` is empty).

Method: read both committed files; ran the committed `main` unit test against both implementations read-only (copies of each ref's `virtualization.rb` selected via `-I`), and ran a 37-scenario harness through `MockLoader` (`backend.stub :file` with OpenStruct `exist?/content`, files absent unless listed; commands exit 1 / empty stdout unless mocked, per Train's `Mock::Connection#command_not_found`, `train-core-3.16.5/lib/train/transports/mock.rb:112-120`). Every table value below is harness output, not hand-tracing, unless marked. Nothing in the repo was modified.

Hard results first:
- `main`'s committed unit test passes on `main` (2 runs, 5 assertions, 0 failures) and **fails on the first draft**: `Expected: "virtualization" Actual: "containerd"` (`test/unit/resources/virtualization_test.rb:35`, scenario "no virtualization platform found"). The first-draft commit does not touch the test file (`git diff --stat` lists only `PR.md`, `virt.rb`, `test-virtualization.rb`, `virtualization-enhancement.zip`).
- `bundle exec chefstyle` on the first-draft file: **422 offenses** (388 `Style/StringLiterals`, 14 `Style/NumericPredicate`, 8 `Layout/MultilineOperationIndentation`, 1 `Lint/ShadowedException`, 1 `Lint/UselessAssignment`, ...). `main` file: 0. `rake lint` is chefstyle (`Rakefile:41-43`).

---

## 1. Ranked findings

### Breaking

1. **breaking — `resource_id` for "nothing detected" changes `"virtualization"` → `"physical-system"`.**
   `main:virt.rb:63` `@virtualization_data[:system] || "virtualization"` vs `wip:virt.rb:239` `@data[:system] || "physical-system"`. `resource_id` is emitted in the JSON reporter (`lib/inspec/reporters/json.rb:50,55-64`) and schema (`lib/inspec/schema/exec_json.rb:41`) and is pinned by the existing unit test (`main:test/unit/resources/virtualization_test.rb:35`). Core convention is "identifier or the resource's own name": `platform.rb:97` `@platform.name || "platform"`, `os.rb:31` `@platform.name || "OS"`, `kernel_parameter.rb:33`, `service.rb:301`, `users.rb:311`; docs say resource_id is "the unique identifier for a resource" (`docs-chef-io/content/inspec/profiles/custom_resources.md:82-83`). `"physical-system"` also asserts a conclusion the docs explicitly warn is unreliable: "For unsupported virtualization platforms this can result in false positives" (`docs:77`). Triggers: every bare-metal/undetected host, and every Windows physical host.

2. **breaking — `openstack` detection removed entirely.** `main:virt.rb:124-131,315` (`nova` binary ⇒ `system "openstack"`, `role "host"`); the first draft has no occurrence of `openstack`/`nova`. Docs list `openstack (host role only)` (`docs:90`). Hand-traced (cannot mock `command.exist?` in MockLoader: `lib/inspec/resources/command.rb:77` returns false on mock): main ⇒ `openstack`/`host`; first draft ⇒ `nil`/`nil`, `physical_system? == true`.

3. **breaking — `kubepods` system value removed.** `main:virt.rb:223-225` sets `system "kubepods"` for a `kubepods` cgroup. The first draft never produces it; same input ⇒ `system "container"`, `k8s_distribution "vanilla"` (`wip:virt.rb:585-598`; harness S3). Any profile with `only_if { virtualization.system == 'kubepods' }` silently stops matching. The value is not in the docs list (`docs:83-95`) but it has shipped since `cd893ce1e`.

4. **breaking — Docker/LXC containers on systemd cgroup drivers without `/.dockerenv` are no longer detected.** `main:virt.rb:219-220` matches `^\d+:[^:]+:/[^/]+/(lxc|docker)-.+$` (e.g. `12:pids:/system.slice/docker-abc.scope`). The first draft's only cgroup patterns are `%r{^\d+:[^:]+:/(lxc/)?docker/.+$}` (`wip:virt.rb:795`) and `%r{^\d+:[^:]+:/lxc/}` (`wip:virt.rb:813`). Harness S2/S2b: main `docker`/`guest` and `lxc`/`guest`; first draft `nil`/`nil`, `physical? true`.

5. **breaking + bug — cloud/orchestrator "fallback" branches return `true` without setting `system`/`role`, short-circuiting all VM detection.** `wip:virt.rb:946-952` (EC2 `product_uuid`), `973-979` (GCE DMI), `999-1004` (`/var/lib/waagent`), `736-759` (Nomad dirs/process). Because `detect_linux` is `return if ...` (`wip:virt.rb:255-296`), the resource ends with `system nil`, `physical? true`, yet `cloud? true` / `orchestrator "nomad"`. Harness: S18 Azure VM with IMDS blocked: main `hyper-v`/`guest`; first draft `nil`/`nil`, `physical? true`, `cloud_provider "azure-vm"`. S17 Nomad client on VMware: main `vmware`/`guest`; first draft `nil`/`nil`, `physical? true`, `orchestrator "nomad"`. `virtual_system?` flips true→false on both.

6. **breaking — Kubernetes *nodes* (hosts) are classified as pods (role `guest`).** `in_kubernetes_pod?` returns true for `/var/lib/kubelet` and `/etc/kubernetes` (`wip:virt.rb:623-624`), which are node paths. `detect_container_runtime` then finds `/run/containerd` or `pgrep containerd` (`wip:virt.rb:651-653`, only possible on a host) so `system` becomes `"containerd"`, `role "guest"`, `k8s_pod_name` = node hostname (`wip:virt.rb:636`). Harness S20 (kubeadm node that is a KVM guest): main `kvm`/`guest`; first draft `containerd`/`guest`, `orchestrator kubernetes`. S20b (bare-metal k3s node): main `nil`, `physical? true`; first draft `containerd`/`guest`, `k8s_distribution "k3s"`, `physical? false`. Also the k8s host `pgrep k3s`/`pgrep rancher-agent`/`pgrep -f microk8s`/`/var/snap/microk8s`/`/var/lib/k0s` checks (`wip:virt.rb:445-446,477-478,530-537,548-555`) can only succeed on hosts, not inside a pod, so they are host signals labelled guest.

7. **breaking — `/var/snap/lxd` makes any machine with the LXD snap a `lxd`/`host`, ahead of all VM detection.** `wip:virt.rb:841-846`, run at `wip:virt.rb:275` before KVM/VMware/Xen (`289-293`). main only checks `/var/lib/lxd/devlxd` (`main:virt.rb:258`). Harness S6b (VMware guest with `/var/snap/lxd` present): main `vmware`/`guest`; first draft `lxd`/`host`, `virtual_system? false`. UNVERIFIED: Ubuntu Server cloud images may ship the `lxd` snap preinstalled, which would make this the common case for Ubuntu VMs.

8. **breaking — detection-order inversion on hosts with both VirtualBox and KVM modules.** main checks virtualbox before kvm (`main:virt.rb:308,313`); the first draft checks kvm before virtualbox (`wip:virt.rb:289,291`). Harness S8: main `vbox`/`host`; first draft `kvm`/`host`.

9. **breaking — EC2 Xen-generation instances now report `kvm`** (and `hypervisor "aws-nitro"`). `detect_aws_ec2` runs before `detect_xen` (`wip:virt.rb:283` vs `292`) and hard-codes `system "kvm"` / `hypervisor "aws-nitro"` (`wip:virt.rb:935-937`). Harness S19 (`/proc/xen/capabilities` present + IMDS answers): main `xen`/`guest`; first draft `kvm`/`guest`. Factually wrong for t2/m4-class instances.

10. **breaking — Windows VirtualBox value changes `"virtualbox"` → `"vbox"`.** `main:virt.rb:339-340` vs `wip:virt.rb:1284-1285`; docs promise `virtualbox` on Windows (`docs:97-103`). Harness W1.

11. **breaking (behaviour change, arguably a fix) — Windows Xen/KVM now detected; Windows WMI failure now silent.** main indexes the parsed JSON with a symbol (`main:virt.rb:343` `windows_computer_system[:manufacturer]`) so the Xen/QEMU branch never fires (harness W2/W3: main `nil`); the first draft uses `"Manufacturer"` (`wip:virt.rb:1275`) ⇒ `xen`/`kvm`. That matches the docs (`docs:97-103`) so it is a bug fix, but it changes answers and should be declared. Separately, on WMI/JSON failure main raises `NoMethodError` (`nil["Model"]`, `main:virt.rb:334`) which `supersuper_initialize` turns into a *skipped* resource (`lib/inspec/resource.rb:67-68`; harness W6 `physical?=nil`), while the first draft rescues `StandardError` (`wip:virt.rb:1309`) and reports `physical? true` (harness W6). Silent "physical" on a failed probe is worse than a skip.

12. **breaking (minor) — public `params` method removed.** `main:virt.rb:57-60` (always nil, commented broken). Absent in the first draft ⇒ `NoMethodError`. Low impact; declare it.

### Bugs

13. **bug — up to 5-6 un-timed `curl` calls to link-local/metadata endpoints on every instantiation of any non-container Linux target.** Harness S0/S7-S15 show 5 network commands for every VM/bare-metal scenario, 6 for VMware (`wip:virt.rb:1198` adds another). Commands: Azure IMDS twice (`904`, `987`), AWS PUT token (`929`), `metadata.google.internal` (`960`), DigitalOcean (`1011`). None pass `--connect-timeout`/`--max-time`. Where 169.254.169.254 is routed to a gateway that drops packets, each call waits for the TCP SYN retry budget (exact duration UNVERIFIED). A resource is instantiated per `describe`/`only_if`; Train's command cache (`lib/inspec/backend.rb:47-50`, on by default) dedupes identical commands within one run, which bounds but does not remove the cost. main runs 0-1 commands (harness).

14. **bug — shell injection surface: HTTP response bodies and `/proc/1/environ` content are interpolated into shell commands.** `wip:virt.rb:366-368` and `929-932` interpolate `token` (whatever 169.254.169.254 returned; on non-AWS hosts it is an error body) inside double quotes, where `$(…)`/backticks are evaluated. `wip:virt.rb:860-864` interpolates `metadata_uri.split('=')[1]` from `/proc/1/environ`. On non-AWS clouds the token check `!token.empty?` (`367`, `931`) is also satisfied by an error body (Azure/GCP metadata servers answer on that IP; exact bodies UNVERIFIED).

15. **bug — `container?` is false for pods on vanilla Kubernetes and on CRI-O.** `wip:virt.rb:174` list is `docker lxc podman containerd lxd`, but `system` can be `"container"` (`589`, `601`, `867`, `888`, `910`) or `"cri-o"` (`659`). Harness S3: `system "container"`, so `container? == false` while `kubernetes? == true`. Also `virtual_machine?` (`195`) omits `utm` (`1034`).

16. **bug — `system` for a Kubernetes pod depends on distro, not on the runtime.** `set_kind_data` forces `system 'docker'` (`wip:virt.rb:351`) while `set_k8s_cloud_data`/generic use `detect_container_runtime || 'container'` (`589`, `601`). Same pod image ⇒ `docker` on kind, `container` elsewhere. `detect_container_runtime` also returns `'docker'` for `/.dockerenv` (`663-666`), so harness S3b (pod with `/.dockerenv`) gives `system "docker"`, `container_runtime nil` — `container_runtime` is nil because `detect_kubernetes_generic` never sets it (`585-598`) even though `set_k8s_cloud_data` does (`603`).

17. **bug — `in_kubernetes_pod?` is also true on EC2 hosts running self-managed k8s ⇒ `k8s_distribution "eks"`, `cloud_provider "eks"`.** `detect_kubernetes_eks` treats "IMDS answers with an `ami-`" as EKS (`wip:virt.rb:366-372`); any kubeadm/k3s node on EC2 qualifies (given finding 6). `which oc` ⇒ OpenShift (`433-436`), `which aws-iam-authenticator` ⇒ EKS (`376-379`) are tool-presence, not platform, signals.

18. **bug — local dev tools reported as `cloud_provider`, so `cloud?` is true on laptops.** `cloud_provider` set to `kind` (`356`), `minikube` (`460`), `docker-desktop` (`510`), `k3d` (`569`), `orbstack` (`494`), `microk8s` (`531`), `k0s` (`549`), `colima` (`1072`); `cloud?` is `!cloud_provider.nil?` (`189-191`). PR.md's own example works around it: `only_if { virtualization.cloud? && !virtualization.kind? }` (`PR.md:194`).

19. **bug — `aws?` is false on ECS Fargate.** `aws?` tests `include?('aws')`, `include?('eks')`, `== 'ec2'` (`wip:virt.rb:222-224`); Fargate sets `cloud_provider 'ecs-fargate'` (`870`). `== 'ec2'`/`== 'gce'` branches (`223`, `227`) are dead: the values produced are `aws-ec2`/`gcp-gce` (`938`, `966`).

20. **bug — dead or never-matching checks.** `detect_utm` requires `inspec.os.darwin?` (`wip:virt.rb:1028`) but `detect_linux` only runs when `inspec.os.linux?` (`110-111`) ⇒ unreachable. `ip route show` output never contains `_default` (`703`) or `kind` (`340-341`); route tables do not print Docker network names. `detect_docker_swarm` requires being inside a container (`724`) then checks the host-side path `/var/lib/docker/swarm` (`727`). Compose detection via `COMPOSE_PROJECT`/`COMPOSE_SERVICE` in `/proc/1/environ` (`713`): Compose records project/service as container labels, not environment variables (UNVERIFIED). `detect_docker_base` is executed three times (`692`, `724`, `778`) and mutates `@data` even when the caller returns false (`781-790`).

21. **bug — `detect_kubernetes_*` always report `confidence 'high'`** (`447`, `479`, `531`, `549`...) even for single weak signals, contradicting PR.md's definition (`PR.md:231-233`). `confidence`, `detection_method`, `vm_cloud_provider`, `k8s_service_account` have no accessor (accessors are `wip:virt.rb:124-166`), so `its('confidence')` in `PR.md:208` raises `NoMethodError`. `metadata` returns the live internal hash (`164-166`) including a non-deterministic `detection_time: Time.now` (`107`).

### Risk / nit

22. **risk — binary `virtualization-enhancement.zip` (12 KB) and two root-level files committed** (`git show --stat 52e30ce`: `VIRTUALIZATION-ENHANCEMENT-PR.md`, `test-virtualization.rb`, `virtualization-enhancement.zip`). None belong in `inspec/inspec`; the zip duplicates the three files. `test-virtualization.rb` is a profile control (`control '...' do`) at repo root, not a unit test.
23. **nit — style:** single-quoted strings throughout (chefstyle enforces double; 388 offenses), `has_kubectl?` naming, `rescue JSON::ParserError, StandardError` (`1309`, shadowed exception), "Method 4" with no "Method 3" (`622`), `Inspec::Log.debug` lines dropped (`main:virt.rb:111,115`), `return unless inspec.os.windows?` redundant (`1269`), `hypervisor` values `aws-nitro`/`gcp-compute`/`azure-hypervisor` are vendors, not hypervisors (`937`, `965`, `992`).

---

## 2. main vs first draft per scenario (harness output; `rid` = `resource_id`, `phys` = `physical_system?`, `virt` = `virtual_system?`)

| # | Scenario (files present; others absent) | main: system/role/rid/phys/virt | First draft: system/role/rid/phys/virt (+new fields) | Verdict |
|---|---|---|---|---|
| S0 | nothing | nil/nil/`virtualization`/T/F | nil/nil/`physical-system`/T/F | **breaking** (rid) |
| S1 | `/.dockerenv` | docker/guest/docker/F/T | same; `container_runtime docker` | same |
| S2 | cgroup `/system.slice/docker-abc.scope`, no `.dockerenv` | docker/guest/docker/F/T | nil/nil/`physical-system`/T/F | **breaking** |
| S2b | cgroup `/system.slice/lxc-web1.scope` | lxc/guest/lxc/F/T | nil/nil/`physical-system`/T/F | **breaking** |
| S3 | cgroup `kubepods`, SA token+namespace | kubepods/guest/kubepods/F/T | container/guest/container/F/T; orch kubernetes, dist vanilla, runtime nil | **breaking** (system) |
| S3b | S3 + `/.dockerenv` | docker/guest/docker/F/T | docker/guest/docker/F/T; orch kubernetes, runtime nil | same core; runtime nil is a bug |
| S4 | `/proc/1/environ` `container=podman`, cgroup "" | podman/guest/podman/F/T | same; runtime podman | same |
| S5 | cgroup `/lxc/web1` | lxc/guest/lxc/F/T | same; runtime lxc | same |
| S6 | `/dev/lxd/sock` | lxd/guest/lxd/F/T | same | same |
| S6b | VMware DMI + `/var/snap/lxd` | vmware/guest/vmware/F/T | lxd/host/lxd/F/**F** | **breaking** |
| S7 | `/proc/xen/capabilities` "" | xen/guest/xen/F/T | same; hypervisor xen | same (5 curls) |
| S7b | `/proc/xen/capabilities` `control_d` | xen/host/xen/F/F | same | same |
| S8 | `/proc/modules` vboxdrv + `/sys/.../misc/kvm` | vbox/host/vbox/F/F | **kvm**/host/kvm/F/F | **breaking** |
| S8b | `/proc/modules` vboxguest | vbox/guest/vbox/F/T | same | same |
| S9 | cpuinfo `QEMU Virtual CPU` | kvm/guest/kvm/F/T | same | same |
| S10 | `/sys/.../misc/kvm`, no `hypervisor` flag | kvm/host/kvm/F/F | same | same |
| S11 | DMI `VMware Virtual Platform` | vmware/guest/vmware/F/T | same; 6 curls | same |
| S12 | DMI `Virtual Machine` | hyper-v/guest/hyper-v/F/T | same | same |
| S13/13b | `/proc/vz` / `/proc/bc/0` | openvz guest / host | same | same |
| S14 | PCI `1ab84000` | parallels/guest/parallels/F/T | same | same |
| S15 | `/proc/self/status` `VxID: 42` | linux-vserver/guest/…/F/T | same | same |
| S16 | `nova` binary (hand-traced) | openstack/host/openstack/F/F | nil/nil/`physical-system`/T/F | **breaking** |
| S17 | `/etc/nomad.d` + VMware DMI | vmware/guest/vmware/F/T | nil/nil/`physical-system`/**T**/F; orch nomad | **breaking + bug** |
| S18 | DMI `Virtual Machine` + `/var/lib/waagent`, IMDS blocked | hyper-v/guest/hyper-v/F/T | nil/nil/`physical-system`/**T**/F; cloud azure-vm | **breaking + bug** |
| S18b | DMI `Google Compute Engine`, metadata blocked | nil/nil/`virtualization`/T/F | nil/nil/`physical-system`/T/F; cloud gcp-gce | rid breaking; `physical? && cloud?` inconsistent |
| S19 | `/proc/xen/capabilities` + IMDS answers `i-…` | xen/guest/xen/F/T | **kvm**/guest/kvm/F/T; hypervisor aws-nitro | **breaking + wrong** |
| S19b | `product_uuid` `EC2…`, IMDS blocked | nil/nil/`virtualization`/T/F | nil/nil/`physical-system`/T/F; cloud aws-ec2 | rid breaking; inconsistent |
| S20 | `/etc/kubernetes`, `/var/lib/kubelet`, `/run/containerd` + cpuinfo QEMU | kvm/guest/kvm/F/T | **containerd**/guest/containerd/F/T; orch kubernetes | **breaking** (host as pod) |
| S20b | k3s node, bare metal | nil/nil/`virtualization`/T/F | containerd/guest/containerd/**F**/**T**; dist k3s | **breaking** (host as pod) |
| S21 | EC2 Nitro, nothing else | nil/nil/`virtualization`/T/F | kvm/guest/kvm/F/T; cloud aws-ec2 | new detection (undocumented) |
| W1 | Win `Model VirtualBox` | virtualbox/guest/virtualbox/F/T | **vbox**/guest/vbox/F/T | **breaking** |
| W2 | Win `Manufacturer Xen` | nil/nil/`virtualization`/T/F | xen/guest/xen/F/T | change (fixes main bug; matches docs) |
| W3 | Win `Manufacturer QEMU` | nil/nil/`virtualization`/T/F | kvm/guest/kvm/F/T | change (fixes main bug; matches docs) |
| W4 | Win `Model Virtual Machine` | hyper-v/guest/hyper-v/F/T | same | same |
| W5 | Win Dell | nil/nil/`virtualization`/T/F | nil/nil/`physical-system`/T/F | rid breaking |
| W6 | Win WMI fails | resource skipped (NoMethodError), phys nil | nil/nil/`physical-system`/T/F silently | change (silent false "physical") |

Detection order: both are first-match-wins (`main:virt.rb:306-318`; `wip:virt.rb:255-296`). main: xen → docker → vbox → lxd → container(lxc/docker/kubepods/podman/lxc-host) → vserver → kvm(cpuinfo) → kvm(sys) → openvz → openstack → parallels → vmware → hyperv. First draft: 13 k8s variants → compose → swarm → nomad → podman → docker → lxc → lxd → fargate → cloud-run → aci → ec2 → gce → azure → digitalocean → utm(dead) → colima → kvm → vmware → vbox → xen → hyper-v → parallels → openvz → vserver.

## 3. What conventions and docs say

- `resource_id` fallback: resource's own name/stable label (`platform.rb:96-98`, `os.rb:30-32`, `sys_info.rb:115-117`, `kernel_parameter.rb:32-34`; base returns `""` when unset, `lib/inspec/resource.rb:37-41`). main's `"virtualization"` conforms; `"physical-system"` does not and encodes a claim the docs qualify (`docs:77`).
- `system` names and roles are enumerated in `docs:79-103` (Linux: docker, hyper-v, kvm, linux vserver, lxc/lxd, openstack host-only, openvz, parallels, virtualbox, vmware, xen; Windows: hyper-v, kvm, vmware, virtualbox, xen). The first draft drops `openstack`, renames Windows `virtualbox`, and adds undocumented values (`container`, `containerd`, `cri-o`, `runc`, `utm`) with no docs change.
- `virtual_system?` = "a guest was detected" (`docs:73`); `physical_system?` = "no virtualization platform is detected" (`docs:77`). The first draft's fallback branches violate both (finding 5).
- Unit-test convention: `MockLoader`, Train mock where unmocked files do not exist and unmocked commands exit 1 (`mock.rb:112-124`); `command.exist?` is always false under mock (`command.rb:77`), so `which`-style checks must be mocked as commands.

## 4. New detections on their own terms

Covered in findings 6, 9, 13-21. Summary of misfires: host paths/processes (`/etc/kubernetes`, `/var/lib/kubelet`, `/run/containerd`, `pgrep containerd|k3s|k0s|crio|dockerd|runc|rancher-agent|microk8s|nomad`) used as *guest* signals; tool presence (`oc`, `aws-iam-authenticator`, `kubectl`) used as platform signals; EC2 ≡ EKS; local tools as clouds; `ip route` greps that cannot match; Azure IMDS queried twice and before `hyper-v` DMI; `detect_vmware_cloud_provider` does an un-authenticated IMDSv1 call (`1198`); no Windows additions beyond the key fix; macOS path (`detect_utm`) unreachable.

## 5. First-draft PR description claims contradicted by the code

| Claim | Contradiction |
|---|---|
| "Breaking Changes: **None.** All existing functionality is preserved. This is purely additive." (`PR.md:212-214`) | Findings 1-12; harness rows S0, S2, S2b, S3, S6b, S8, S16-S20b, W1. The committed unit test fails on the first-draft code. |
| "All existing methods remain unchanged" (`PR.md:102`) | `resource_id` fallback changed (`wip:virt.rb:239`); `params` removed (`main:virt.rb:57-60`). |
| "`system` - Still returns the primary system type" (`PR.md:103`) | `kubepods`, `openstack`, Windows `virtualbox` no longer returned; systemd-cgroup docker/lxc no longer detected. |
| "Detection order ... 3. Container orchestrators 4. Serverless 5. Containers (Podman, Docker, LXC, LXD) 6. Cloud VMs 7. Traditional VMs" (`PR.md:220-227`) | Actual order: orchestrators → containers → serverless → cloud VMs → traditional (`wip:virt.rb:255-296`); serverless comes after containers, not before. |
| "All detection methods use reliable indicators only ... Process checks (`pgrep containerd`...)" (`PR.md:128-130`) | `pgrep` inside a pod cannot see host daemons; these checks fire only on hosts (finding 6). |
| "`high` - Definitive detection via multiple indicators; `medium` - Single reliable indicator" (`PR.md:231-232`) | Single-signal checks are labelled `high` (`wip:virt.rb:447,479,531,549,569`); `/.dockerenv` alone is `high` (`787`). |
| "`virtualization.aws?` # Is this AWS (EC2/EKS/Fargate)?" (`PR.md:74`) | `aws?` is false for `ecs-fargate` (`wip:virt.rb:222-224` vs `870`). |
| `its('confidence') { should eq 'high' }` (`PR.md:208`) | No `confidence` accessor (`wip:virt.rb:124-166`). |
| "Container runtime detection may return `nil` ... The `system` property will still correctly identify the container technology" (`PR.md:237-239`) | On vanilla k8s `system` is the placeholder `"container"` (`589`), not a technology; harness S3. |
| Checklist "[x] Backwards compatibility maintained" (`PR.md:285`) | See above. |
| "[ ] Unit tests added (TODO - needs InSpec unit test framework)" (`PR.md:290`) | The framework exists and is used by the existing test for this resource (`test/unit/resources/virtualization_test.rb`, `test/helpers/mock_loader.rb`). |
| "TESTED (verified in real environments): Kubernetes pod detection (OrbStack cluster)" (`PR.md:110-111`) | UNVERIFIED either way; no artefact in the commit. `test-virtualization.rb` asserts only non-nil/`guest`, so it would also pass on a mis-classified node. |
| "Detection Reliability ... NOT USED: Environment variables (except `/proc/1/environ`)" (`PR.md:135-136`) | Consistent with code, but `/proc/1/environ` content is interpolated into a shell command (`860-864`). |

## 6. Tests

**Committed tests.** `main`'s test (`main:test/unit/resources/virtualization_test.rb`) has two cases. The "nothing detected" case uses an inverted stub: files *in the list* report `exist? false`, every other path reports `exist? true` with `content nil` (`:7-13`). It passes on main only because main's untested branches tolerate nil content, and it pins `resource_id == "virtualization"`, `system nil`, `role nil`. The podman case pins `podman`/`guest`. Neither pins xen/kvm/vmware/vbox/lxd/openvz/vserver/parallels/openstack/Windows, so main's contract is mostly unpinned. The first-draft ref adds no tests; the committed test fails on it (above). The uncommitted working-tree edit (not part of the first draft) switches to absent-by-default mocking and still expects `"virtualization"`; it also fails on the first draft (`Expected: "virtualization" Actual: "physical-system"`, `test/unit/resources/virtualization_test.rb:22`).

**Proposed suite** (MockLoader; one `describe` per scenario; `backend.stub :file` with absent-by-default OpenStruct or `mock.files=` with `Train::Transports::Mock::Connection::File`; commands via `backend.backend.mock_command(cmd, stdout, "", 0)` — note `mock_command` stores under the raw string while lookup hashes the string, so set both keys or use `MockLoader.mock_command`; for Windows, `MockLoader.new(:windows)` and mock the exact script `"Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop | ConvertTo-Json"`). Each test asserts `system`, `role`, `resource_id`, `physical_system?`, `virtual_system?` exactly.

Regression tests pinning main (must pass unchanged on `main` first):
1. nothing detected (no files, no commands) ⇒ `nil`, `nil`, `"virtualization"`, `true`, `false`; also `to_s == "Virtualization Detection"`.
2. `/.dockerenv` ⇒ `docker`/`guest`/`"docker"`/false/true.
3. cgroup `.../docker/<id>` ⇒ docker/guest.
4. cgroup `/system.slice/docker-<id>.scope` ⇒ docker/guest.
5. cgroup `/lxc/<name>` ⇒ lxc/guest.
6. cgroup `/system.slice/lxc-<name>.scope` ⇒ lxc/guest.
7. cgroup `/kubepods/...` ⇒ `kubepods`/guest.
8. `/proc/1/environ` `container=podman` ⇒ podman/guest.
9. `/dev/lxd/sock` ⇒ lxd/guest; `/var/lib/lxd/devlxd` ⇒ lxd/host.
10. `/proc/xen/capabilities` "" ⇒ xen/guest; `control_d` ⇒ xen/host.
11. `/proc/modules` `vboxdrv` ⇒ vbox/host; `vboxguest` ⇒ vbox/guest.
12. vboxdrv + `/sys/devices/virtual/misc/kvm` ⇒ vbox/host (order pin).
13. cpuinfo `QEMU Virtual CPU` ⇒ kvm/guest.
14. `/sys/devices/virtual/misc/kvm` + cpuinfo `hypervisor` ⇒ kvm/guest; without ⇒ kvm/host.
15. `/proc/vz` ⇒ openvz/guest; `/proc/bc/0` ⇒ openvz/host.
16. `/proc/bus/pci/devices` containing `1ab84000` ⇒ parallels/guest.
17. `/proc/self/status` `VxID: 0` ⇒ vserver/host; `VxID: 42` ⇒ vserver/guest.
18. DMI `VMware Virtual Platform` ⇒ vmware/guest.
19. DMI `Virtual Machine\n` ⇒ hyper-v/guest.
20. openstack: stub `Inspec::Resources::Virtualization#nova_exists?` (or refactor to a mockable command) ⇒ openstack/host.
21. Windows: `Model "Virtual Machine"` ⇒ hyper-v/guest; `Model "VMware Virtual Platform"` ⇒ vmware; `Model "VirtualBox"` ⇒ `virtualbox`; `Manufacturer "Xen"` ⇒ xen; `Manufacturer "QEMU"` ⇒ kvm (the last two are new behaviour vs main's symbol-key bug and are declared in the PR description); unknown ⇒ nil/`"virtualization"`/`physical_system? true`; WMI failure ⇒ decide and pin (skip vs physical).
22. "host also runs containers" pins: KVM host with `/proc/self/cgroup` root-only ⇒ kvm/host; VMware guest with `/var/snap/lxd` ⇒ vmware/guest; VMware guest with `/etc/nomad.d` ⇒ vmware/guest; k8s node (`/etc/kubernetes`, `/var/lib/kubelet`, `/run/containerd`) on a KVM guest ⇒ kvm/guest, `kubernetes? == false`.

Tests for any additive feature kept in the PR (exact expected values):

23. k8s pod (SA token + namespace `prod`, cgroup kubepods, no `.dockerenv`, all commands exit 1) ⇒ `kubernetes? true`, `orchestrator "kubernetes"`, `k8s_namespace "prod"`, `container? true`, `system`/`role` equal to the pinned main answer for that input, `cloud? false`.
24. kind pod (`hostname` ⇒ `kind-control-plane`) ⇒ `k8s_distribution "kind"`, `cloud? false`.
25. EC2 (mock PUT token ⇒ `TOKEN`, mock GET with that token ⇒ `i-0abc`) ⇒ `cloud_provider "aws-ec2"`, `aws? true`, and `system`/`role` consistent with hypervisor detection (xen when `/proc/xen/capabilities` present).
26. Azure VM with IMDS blocked + waagent + DMI `Virtual Machine` ⇒ hyper-v/guest, `cloud_provider "azure-vm"`, `physical_system? false`.
27. Every fallback branch: `physical_system?` is never true while `cloud?`/`orchestrator` is set.
28. Command budget: assert the list of commands issued for the "nothing detected" scenario is empty or bounded (prepend a tracer on `Train::Transports::Mock::Connection#run_command_via_connection`, as the harness does) and that every `curl` has `--connect-timeout`/`--max-time`.
29. No command string contains interpolated remote data (or mock a token containing `$(touch /tmp/x)` and assert the issued command is quoted/escaped).
30. Fargate ⇒ `aws? true`.

## 7. Recommended PR shape for inspec/inspec (as reviewed)

The review recommended not submitting the first-draft commit and splitting the work into a bug-fix PR, an
additive metadata PR, and a separate cloud-metadata design discussion. The plan in
`VIRTUALIZATION-ENHANCEMENT-PR.md` supersedes this section: it keeps main's detection chain unchanged and
adds independent, lazily evaluated layers, which removes the need for most of the split.

Items the reviewer could not verify (marked above): Ubuntu Server shipping the `lxd` snap by default;
Docker Compose not exporting `COMPOSE_*` into containers; exact Azure/GCP metadata-server bodies on
unknown paths; TCP SYN retry duration on a blackholed route; the author's OrbStack manual test.
