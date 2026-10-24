# Enhancement: Comprehensive Virtualization Detection Resource

## Summary

This PR significantly enhances the `virtualization` InSpec resource with modern container orchestration, cloud provider detection, and Kubernetes distribution identification.

## Motivation

The original virtualization resource was designed primarily for VM detection (Xen, KVM, VMware) with basic container support (Docker, LXC). Modern infrastructure includes:

- **Container orchestrators**: Kubernetes, Nomad, Docker Swarm, ECS
- **Cloud providers**: EKS, GKE, AKS, kind, OrbStack
- **K8s distributions**: kind, k3s, k3d, minikube, MicroK8s, K0s, OpenShift, Rancher
- **Serverless platforms**: ECS Fargate, Cloud Run, Azure Container Instances
- **Local development**: Docker Desktop, OrbStack, Colima, UTM

Security and compliance testing needs to understand the full context of where code is running.

## Changes

### New Detection Capabilities

#### Kubernetes Distributions
- **kind** - Kubernetes in Docker (local development)
- **k3s** - Lightweight Kubernetes (edge/IoT)
- **k3d** - K3s in Docker (CI/CD)
- **K0s** - Zero friction Kubernetes
- **MicroK8s** - Snap-based Kubernetes (Ubuntu)
- **Docker Desktop** - Built-in Kubernetes
- **OrbStack** - macOS/Linux local Kubernetes
- **Minikube** - Local Kubernetes (enhanced)
- **OpenShift** - Red Hat enterprise Kubernetes
- **Rancher** - Enterprise Kubernetes platform

#### Cloud-Managed Kubernetes
- **EKS** - Amazon Elastic Kubernetes Service
- **GKE** - Google Kubernetes Engine
- **AKS** - Azure Kubernetes Service
- **EKS Anywhere** - On-premises EKS
- **Anthos** - Google hybrid/multi-cloud
- **DOKS** - DigitalOcean Kubernetes

#### Container Orchestrators
- **Docker Compose** - Multi-container applications
- **Docker Swarm** - Native Docker clustering (enhanced)
- **Nomad** - HashiCorp workload orchestrator (enhanced)

#### Serverless Containers
- **ECS Fargate** - AWS serverless containers
- **Google Cloud Run** - GCP serverless containers
- **Azure Container Instances** - Azure serverless

#### VM Platforms (Enhanced)
- **UTM** - macOS QEMU-based virtualization
- **Colima** - macOS container runtime
- All existing VM detections improved with better metadata

### New Helper Methods

```ruby
# Container detection
virtualization.container?          # Is this any container?
virtualization.kubernetes?          # Is this Kubernetes?
virtualization.kind?                # Is this a kind cluster?
virtualization.cloud?               # Is this in any cloud?

# VM detection
virtualization.virtual_machine?    # Is this a VM?
virtualization.virtual_host?       # Is this a hypervisor host?
virtualization.virtual_guest?      # Is this a VM guest?
virtualization.physical?           # Is this physical hardware?

# Cloud-specific
virtualization.aws?                # Is this AWS (EC2/EKS/Fargate)?
virtualization.gcp?                # Is this GCP (GCE/GKE/Cloud Run)?
virtualization.azure?              # Is this Azure (VM/AKS/ACI)?
```

### Rich Metadata

The resource now provides detailed metadata:

```ruby
virtualization.metadata
# =>  {
#   system: 'docker',
#   role: 'guest',
#   container_runtime: 'containerd',
#   orchestrator: 'kubernetes',
#   cloud_provider: 'eks',
#   k8s_distribution: 'eks',
#   k8s_namespace: 'default',
#   k8s_pod_name: 'my-app-abc123',
#   k8s_node_name: 'ip-10-0-1-50.ec2.internal',
#   confidence: 'high',
#   detection_method: 'eks_imds_v2'
# }
```

### Backwards Compatibility

All existing methods remain unchanged:
- `virtualization.system` - Still returns the primary system type
- `virtualization.role` - Still returns 'host' or 'guest'
- `virtual_system?` - Alias for `virtual_guest?`
- `physical_system?` - Alias for `physical?`

### Testing Status

**TESTED** (verified in real environments):
- ✅ Kubernetes pod detection (OrbStack cluster)
- ✅ Container detection
- ✅ Kubernetes metadata (namespace, pod name)
- ✅ Detection confidence levels
- ✅ Detection method tracking

**UNTESTED** (implemented from research/documentation):
- ⚠️ ECS Fargate detection
- ⚠️ Google Cloud Run detection
- ⚠️ Azure Container Instances
- ⚠️ UTM detection
- ⚠️ Colima detection
- ⚠️ Cloud-managed K8s (EKS, GKE, AKS) - detection logic implemented but not verified
- ⚠️ K8s distributions (k3s, k3d, K0s, MicroK8s, etc.) - detection logic implemented but not verified

### Detection Reliability

All detection methods use **reliable indicators only**:
- ✅ Filesystem checks (`/proc/self/cgroup`, `/.dockerenv`, `/var/lib/k0s`)
- ✅ Process checks (`pgrep containerd`, `pgrep k0s`)
- ✅ Command output (`hostname`, `kubectl get nodes`)
- ✅ Metadata endpoints (AWS IMDS, GCP metadata, Azure IMDS)
- ✅ DMI/SMBIOS data (`/sys/devices/virtual/dmi/id/product_name`)

**NOT USED** (unreliable from remote execution):
- ❌ Environment variables (except when reading `/proc/1/environ` from target)
- ❌ Docker labels (require Docker socket access)
- ❌ kubeconfig files (exist on InSpec host, not target)

## Usage Examples

### Basic Detection

```ruby
describe virtualization do
  its('system') { should eq 'docker' }
  its('role') { should eq 'guest' }
end
```

### Container Detection

```ruby
describe virtualization do
  it { should be_container }
  its('container_runtime') { should eq 'containerd' }
  its('orchestrator') { should eq 'kubernetes' }
end
```

### Kubernetes Detection

```ruby
describe virtualization do
  it { should be_kubernetes }
  its('k8s_distribution') { should eq 'eks' }
  its('cloud_provider') { should eq 'eks' }
  its('k8s_namespace') { should eq 'production' }
end
```

### Cloud Provider Detection

```ruby
describe virtualization do
  it { should be_cloud }
  it { should be_aws }
  its('cloud_provider') { should be_in ['eks', 'ecs-fargate', 'ec2'] }
end
```

### Conditional Testing

```ruby
control 'kind-specific-configuration' do
  only_if { virtualization.kind? }

  describe file('/etc/kubernetes/manifests') do
    it { should be_directory }
  end
end

control 'production-cloud-only' do
  only_if { virtualization.cloud? && !virtualization.kind? }

  describe file('/var/log/app.log') do
    it { should exist }
  end
end
```

### Rich Metadata Access

```ruby
describe virtualization do
  its('metadata') { should include(orchestrator: 'kubernetes') }
  its('k8s_pod_name') { should match(/^my-app-/) }
  its('confidence') { should eq 'high' }
end
```

## Breaking Changes

**None.** All existing functionality is preserved. This is purely additive.

## Implementation Notes

### Detection Order

Detection runs from most specific to least specific:
1. Specific K8s distributions (kind, EKS, GKE, etc.)
2. Generic Kubernetes
3. Container orchestrators (Compose, Swarm, Nomad)
4. Serverless (Fargate, Cloud Run, ACI)
5. Containers (Podman, Docker, LXC, LXD)
6. Cloud VMs (EC2, GCE, Azure)
7. Traditional VMs (KVM, VMware, VirtualBox, etc.)

### Confidence Levels

- `high` - Definitive detection via multiple indicators
- `medium` - Single reliable indicator
- `low` - Heuristic detection (none currently used)

### Container Runtime Detection Limitation

Container runtime detection (`container_runtime` property) may return `nil` when run from inside containers due to isolation. This is expected behavior - pods don't see the host's containerd/cri-o processes.

The `system` property will still correctly identify the container technology (docker, podman, etc.).

## Testing Recommendations

To validate the UNTESTED detection methods, run InSpec in:

**Cloud environments:**
- ECS Fargate task
- Google Cloud Run service
- Azure Container Instance
- EKS cluster
- GKE cluster
- AKS cluster

**Local K8s:**
- kind cluster
- k3s/k3d cluster
- K0s cluster
- MicroK8s cluster
- Docker Desktop Kubernetes

**Specialized:**
- UTM Linux VM on macOS
- Colima container on macOS

## Future Enhancements

Potential future additions:
- **EKS Distro** - AWS Kubernetes distribution
- **Anthos on-prem** - Google hybrid cloud
- **Tanzu Kubernetes Grid** - VMware enterprise K8s
- **Platform9** - Managed Kubernetes
- **KubeEdge** - Edge computing K8s
- **Harvester** - HCI with integrated K8s

## Related Issues

This enhancement addresses several implicit needs:
- Better container orchestration awareness for compliance testing
- Cloud provider detection for conditional controls
- Kubernetes-specific testing capabilities
- Modern development environment support (kind, Docker Desktop, OrbStack)

## Checklist

- [x] Code implements new detection methods
- [x] Backwards compatibility maintained
- [x] Comments added for untested methods
- [x] Only reliable detection methods used (no env vars except /proc/1/environ)
- [ ] Tested in multiple environments (partial - tested in OrbStack K8s)
- [ ] Documentation updated (this PR doc serves as initial documentation)
- [ ] Unit tests added (TODO - needs InSpec unit test framework)
- [ ] Integration tests added (TODO - needs test matrix)

## Testing This Enhancement

You don't need to build InSpec from source to test this enhancement. Just use the enhanced resource as a custom resource in your test profile:

### Quick Test Setup

1. **Extract the zip file:**
   ```bash
   unzip virtualization-enhancement.zip
   ```

2. **Create a test profile structure:**
   ```bash
   mkdir -p my-test-profile/libraries
   mkdir -p my-test-profile/controls
   ```

3. **Copy the enhanced resource to libraries:**
   ```bash
   cp lib/inspec/resources/virtualization.rb my-test-profile/libraries/
   ```

4. **Copy the test control:**
   ```bash
   cp test-virtualization.rb my-test-profile/controls/
   ```

5. **Create an inspec.yml:**
   ```bash
   cat > my-test-profile/inspec.yml <<EOF
   name: virtualization-test
   title: Test Enhanced Virtualization Resource
   version: 1.0.0
   maintainer: Your Name
   summary: Testing enhanced virtualization detection
   EOF
   ```

6. **Run the test:**
   ```bash
   # Against a Kubernetes pod
   inspec exec my-test-profile -t k8s-container://namespace/pod/container

   # Against a Docker container
   inspec exec my-test-profile -t docker://container-name

   # Against local system
   inspec exec my-test-profile

   # Against SSH host
   inspec exec my-test-profile -t ssh://user@host
   ```

### Example Output

```
Profile Summary: 3 successful controls, 2 control failures, 0 controls skipped
Test Summary: 14 successful, 2 failures, 0 skipped

✔  virtualization-detection: Test virtualization detection capabilities
   ✔  Virtualization Detection is expected not to be physical
   ✔  Virtualization Detection system is expected not to be nil
   ✔  Virtualization Detection role is expected to eq "guest"
```

The resource will be loaded from your `libraries/` directory and override the built-in InSpec virtualization resource.

## Author

Aaron Lippold (@lippold) with assistance from Claude Code

---

**Ready for Review and Testing**

This is a significant enhancement that modernizes the virtualization resource for cloud-native environments while maintaining full backwards compatibility.
