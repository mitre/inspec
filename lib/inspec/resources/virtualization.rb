# Enhanced InSpec Virtualization Resource
# Provides comprehensive detection of virtualization, containerization, and cloud environments
#
# This is a complete refactor with:
# - Container runtime detection (Docker, Podman, containerd, CRI-O)
# - Orchestrator detection (Kubernetes, Nomad, Docker Swarm, ECS)
# - Cloud provider detection (kind, EKS, GKE, AKS, EC2, GCE, Azure)
# - Kubernetes distribution detection (kind, k3s, minikube, OpenShift, Rancher)
# - Rich helper methods (container?, kubernetes?, kind?, cloud?)
# - Detailed metadata (namespace, pod name, node name, etc.)

require "hashie/mash"
require "inspec/resources/powershell"
require "json"

module Inspec::Resources
  class Virtualization < Inspec.resource(1)
    name "virtualization"
    supports platform: "unix"
    supports platform: "windows"

    desc "Use the virtualization InSpec audit resource to test virtualization platforms, containers, and cloud environments."

    example <<~EXAMPLE
      # Basic usage
      describe virtualization do
        its('system') { should eq 'docker' }
        its('role') { should eq 'guest' }
      end

      # Container detection
      describe virtualization do
        it { should be_container }
        its('container_runtime') { should eq 'docker' }
      end

      # Kubernetes detection
      describe virtualization do
        it { should be_kubernetes }
        its('orchestrator') { should eq 'kubernetes' }
        its('k8s_distribution') { should eq 'kind' }
        its('cloud_provider') { should eq 'kind' }
      end

      # Cloud provider detection
      describe virtualization do
        it { should be_cloud }
        its('cloud_provider') { should be_in ['eks', 'gke', 'aks'] }
      end

      # Helper method usage
      describe virtualization do
        it { should be_kind }
        it { should be_virtual_guest }
        it { should_not be_physical }
      end

      # Conditional tests based on environment
      control 'kind-specific-test' do
        only_if { virtualization.kind? }

        describe file('/etc/kubernetes/manifests') do
          it { should be_directory }
        end
      end

      # VM detection
      describe virtualization do
        it { should be_virtual_machine }
        its('hypervisor') { should eq 'kvm' }
        its('vm_cloud_provider') { should eq 'aws' }
      end

      # Rich metadata access
      describe virtualization do
        its('metadata') { should include(k8s_namespace: 'default') }
        its('k8s_pod_name') { should_not be_nil }
      end
    EXAMPLE

    def initialize
      @data = {
        # Core virtualization detection
        system: nil,              # Primary system type (docker, kvm, vmware, etc.)
        role: nil,                # host or guest
        physical: false,          # true if no virtualization detected

        # Container-specific
        container_runtime: nil,   # docker, containerd, cri-o, podman, runc
        orchestrator: nil,        # kubernetes, nomad, docker-swarm, ecs, mesos
        cloud_provider: nil,      # kind, eks, gke, aks, ecs-fargate, etc.

        # Kubernetes-specific
        k8s_distribution: nil,    # kind, k3s, minikube, eks, gke, aks, openshift, rancher, vanilla
        k8s_namespace: nil,       # Pod namespace
        k8s_pod_name: nil,        # Pod name
        k8s_node_name: nil,       # Node name
        k8s_service_account: nil, # Service account name

        # VM-specific
        hypervisor: nil,          # kvm, xen, vmware-esxi, hyper-v, virtualbox
        vm_cloud_provider: nil,   # aws-ec2, gcp-gce, azure-vm, digitalocean, linode

        # Detection metadata
        confidence: nil,          # high, medium, low
        detection_method: nil,    # which detection method succeeded
        detection_time: Time.now  # when detection ran
      }

      if inspec.os.linux?
        detect_linux
      elsif inspec.os.windows?
        detect_windows
      end

      # Mark as physical if nothing detected
      @data[:physical] = @data[:system].nil?
    end

    #
    # Core Property Accessors
    #

    def system
      @data[:system]
    end

    def role
      @data[:role]
    end

    def orchestrator
      @data[:orchestrator]
    end

    def cloud_provider
      @data[:cloud_provider] || @data[:vm_cloud_provider]
    end

    def container_runtime
      @data[:container_runtime]
    end

    def hypervisor
      @data[:hypervisor]
    end

    def k8s_distribution
      @data[:k8s_distribution]
    end

    def k8s_namespace
      @data[:k8s_namespace]
    end

    def k8s_pod_name
      @data[:k8s_pod_name]
    end

    def k8s_node_name
      @data[:k8s_node_name]
    end

    def metadata
      @data
    end

    #
    # Boolean Helper Methods
    #

    # Is this a container (any type)?
    def container?
      container_systems = %w{docker lxc podman containerd lxd}
      container_systems.include?(@data[:system])
    end

    # Is this running in Kubernetes?
    def kubernetes?
      @data[:orchestrator] == 'kubernetes'
    end

    # Is this a kind cluster?
    def kind?
      @data[:k8s_distribution] == 'kind' || @data[:cloud_provider] == 'kind'
    end

    # Is this running in any cloud environment?
    def cloud?
      !cloud_provider.nil?
    end

    # Is this a virtual machine?
    def virtual_machine?
      vm_systems = %w{kvm vmware vbox xen hyper-v parallels qemu}
      vm_systems.include?(@data[:system])
    end

    # Is this a virtualization host?
    def virtual_host?
      @data[:role] == 'host'
    end

    # Is this a virtualization guest?
    def virtual_guest?
      @data[:role] == 'guest'
    end

    # Is this a physical system (no virtualization)?
    def physical?
      @data[:physical] == true
    end

    # Backwards compatibility
    alias_method :virtual_system?, :virtual_guest?
    alias_method :physical_system?, :physical?

    #
    # Cloud-specific helpers
    #

    def aws?
      cloud_provider&.include?('aws') || cloud_provider&.include?('eks') || cloud_provider == 'ec2'
    end

    def gcp?
      cloud_provider&.include?('gcp') || cloud_provider&.include?('gke') || cloud_provider == 'gce'
    end

    def azure?
      cloud_provider&.include?('azure') || cloud_provider&.include?('aks')
    end

    #
    # InSpec Framework Methods
    #

    def resource_id
      @data[:system] || "physical-system"
    end

    def to_s
      "Virtualization Detection"
    end

    private

    #
    # Linux Detection Methods
    #

    def detect_linux
      # Detection order: most specific to least specific
      # Container platforms first (including orchestrated)
      return if detect_kind              # Must be before generic k8s
      return if detect_kubernetes_eks
      return if detect_kubernetes_gke
      return if detect_kubernetes_aks
      return if detect_kubernetes_openshift
      return if detect_kubernetes_k3s
      return if detect_kubernetes_k3d
      return if detect_kubernetes_k0s
      return if detect_kubernetes_microk8s
      return if detect_kubernetes_docker_desktop
      return if detect_kubernetes_minikube
      return if detect_kubernetes_rancher
      return if detect_kubernetes_orbstack
      return if detect_kubernetes_generic
      return if detect_docker_compose
      return if detect_docker_swarm
      return if detect_nomad
      return if detect_podman
      return if detect_docker
      return if detect_lxc
      return if detect_lxd

      # Serverless containers
      return if detect_ecs_fargate
      return if detect_cloud_run
      return if detect_azure_container_instances

      # VM platforms
      return if detect_aws_ec2
      return if detect_gcp_gce
      return if detect_azure_vm
      return if detect_digitalocean
      return if detect_utm
      return if detect_colima
      return if detect_kvm
      return if detect_vmware
      return if detect_virtualbox
      return if detect_xen
      return if detect_hyper_v
      return if detect_parallels
      return if detect_openvz
      return if detect_linux_vserver
    end

    #
    # Kubernetes Detection Methods
    #

    def detect_kind
      return false unless in_kubernetes_pod?

      # Method 1: Hostname pattern (most reliable)
      hostname = inspec.command('hostname').stdout.strip
      if hostname =~ /kind-(control-plane|worker)/
        set_kind_data('hostname_pattern', 'high')
        return true
      end

      # Method 2: Check node labels (if kubectl available)
      if has_kubectl?
        node_labels = inspec.command('kubectl get node -o jsonpath=\'{.items[0].metadata.labels}\' 2>/dev/null').stdout
        if node_labels.include?('kind')
          set_kind_data('node_labels', 'high')
          return true
        end

        # Check provider ID
        provider_id = inspec.command('kubectl get node -o jsonpath=\'{.items[0].spec.providerID}\' 2>/dev/null').stdout
        if provider_id.include?('kind://')
          set_kind_data('provider_id', 'high')
          return true
        end
      end

      # Method 3: Check for kind-specific mounts/files
      if inspec.file('/etc/kubernetes/manifests').exist?
        manifests = inspec.command('ls /etc/kubernetes/manifests').stdout
        if manifests.include?('kindnet')
          set_kind_data('kindnet_manifest', 'high')
          return true
        end
      end

      # Method 4: Check Docker with kind network (less reliable)
      if inspec.file('/.dockerenv').exist?
        networks = inspec.command('ip route show 2>/dev/null').stdout
        if networks.include?('kind')
          set_kind_data('docker_kind_network', 'medium')
          return true
        end
      end

      false
    end

    def set_kind_data(method, confidence)
      @data[:system] = 'docker'
      @data[:role] = 'guest'
      @data[:container_runtime] = detect_container_runtime
      @data[:orchestrator] = 'kubernetes'
      @data[:k8s_distribution] = 'kind'
      @data[:cloud_provider] = 'kind'
      @data[:confidence] = confidence
      @data[:detection_method] = "kind_#{method}"
      populate_k8s_metadata
    end

    def detect_kubernetes_eks
      return false unless in_kubernetes_pod?

      # Check for EKS via IMDSv2
      token = inspec.command('curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null').stdout
      if !token.empty?
        ami_id = inspec.command("curl -s -H \"X-aws-ec2-metadata-token: #{token}\" http://169.254.169.254/latest/meta-data/ami-id 2>/dev/null").stdout
        if ami_id.start_with?('ami-')
          set_k8s_cloud_data('eks', 'eks', 'high', 'imds_v2')
          return true
        end
      end

      # Fallback: Check for aws-iam-authenticator or EKS-specific files
      if inspec.command('which aws-iam-authenticator').exit_status.zero?
        set_k8s_cloud_data('eks', 'eks', 'medium', 'iam_authenticator')
        return true
      end

      false
    end

    def detect_kubernetes_gke
      return false unless in_kubernetes_pod?

      # Check GCP metadata service
      metadata = inspec.command('curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name 2>/dev/null').stdout
      if !metadata.empty? && !metadata.include?('curl')
        set_k8s_cloud_data('gke', 'gke', 'high', 'gcp_metadata')
        return true
      end

      # Check for GKE-specific files
      if inspec.file('/home/kubernetes/bin/gke-exec-auth-plugin').exist?
        set_k8s_cloud_data('gke', 'gke', 'medium', 'gke_plugin')
        return true
      end

      false
    end

    def detect_kubernetes_aks
      return false unless in_kubernetes_pod?

      # Check for Azure-specific files
      if inspec.file('/etc/kubernetes/azure.json').exist?
        set_k8s_cloud_data('aks', 'aks', 'high', 'azure_config')
        return true
      end

      # Check for Azure metadata service
      metadata = inspec.command('curl -s -H "Metadata:true" http://169.254.169.254/metadata/instance?api-version=2021-02-01 2>/dev/null').stdout
      if metadata.include?('azureEnvironment')
        set_k8s_cloud_data('aks', 'aks', 'high', 'azure_metadata')
        return true
      end

      false
    end

    def detect_kubernetes_openshift
      return false unless in_kubernetes_pod?

      # Check for OpenShift-specific files
      if inspec.file('/etc/origin/node/node-config.yaml').exist? ||
         inspec.file('/etc/origin/master/master-config.yaml').exist?
        set_k8s_cloud_data('openshift', nil, 'high', 'openshift_config')
        return true
      end

      # Check for oc command
      if inspec.command('which oc').exit_status.zero?
        set_k8s_cloud_data('openshift', nil, 'medium', 'oc_binary')
        return true
      end

      false
    end

    def detect_kubernetes_k3s
      return false unless in_kubernetes_pod?

      # Check for k3s-specific processes or files
      if inspec.command('pgrep k3s').exit_status.zero? ||
         inspec.file('/var/lib/rancher/k3s').exist?
        set_k8s_cloud_data('k3s', nil, 'high', 'k3s_process')
        return true
      end

      false
    end

    def detect_kubernetes_minikube
      return false unless in_kubernetes_pod?

      # Check for minikube hostname
      hostname = inspec.command('hostname').stdout.strip
      if hostname.include?('minikube')
        set_k8s_cloud_data('minikube', 'minikube', 'high', 'hostname')
        return true
      end

      # Check for minikube-specific files
      if inspec.file('/var/lib/minikube').exist?
        set_k8s_cloud_data('minikube', 'minikube', 'high', 'minikube_dir')
        return true
      end

      false
    end

    def detect_kubernetes_rancher
      return false unless in_kubernetes_pod?

      # Check for Rancher agent
      if inspec.command('pgrep rancher-agent').exit_status.zero? ||
         inspec.file('/var/lib/rancher').exist?
        set_k8s_cloud_data('rancher', nil, 'high', 'rancher_agent')
        return true
      end

      false
    end

    def detect_kubernetes_orbstack
      return false unless in_kubernetes_pod?

      # OrbStack is macOS/Linux local Kubernetes
      # Check via kubectl if available (reliable)
      if has_kubectl?
        node_name = inspec.command('kubectl get node -o jsonpath=\'{.items[0].metadata.name}\' 2>/dev/null').stdout
        if node_name.include?('orbstack')
          set_k8s_cloud_data('orbstack', 'orbstack', 'high', 'kubectl_node_name')
          return true
        end
      end

      false
    end

    def detect_kubernetes_docker_desktop
      return false unless in_kubernetes_pod?

      # Docker Desktop Kubernetes
      # Check for docker-desktop node name
      if has_kubectl?
        node_name = inspec.command('kubectl get node -o jsonpath=\'{.items[0].metadata.name}\' 2>/dev/null').stdout
        if node_name.include?('docker-desktop')
          set_k8s_cloud_data('docker-desktop', 'docker-desktop', 'high', 'node_name')
          return true
        end
      end

      # Check hostname
      hostname = inspec.command('hostname').stdout.strip
      if hostname.include?('docker-desktop')
        set_k8s_cloud_data('docker-desktop', 'docker-desktop', 'high', 'hostname')
        return true
      end

      false
    end

    def detect_kubernetes_microk8s
      return false unless in_kubernetes_pod?

      # MicroK8s detection
      # Check for microk8s snap directory
      if inspec.file('/var/snap/microk8s').exist?
        set_k8s_cloud_data('microk8s', 'microk8s', 'high', 'snap_dir')
        return true
      end

      # Check for microk8s processes
      if inspec.command('pgrep -f microk8s').exit_status.zero?
        set_k8s_cloud_data('microk8s', 'microk8s', 'high', 'process')
        return true
      end

      false
    end

    def detect_kubernetes_k0s
      return false unless in_kubernetes_pod?

      # K0s detection
      if inspec.file('/var/lib/k0s').exist? || inspec.file('/etc/k0s').exist?
        set_k8s_cloud_data('k0s', 'k0s', 'high', 'k0s_dir')
        return true
      end

      # Check for k0s process
      if inspec.command('pgrep k0s').exit_status.zero?
        set_k8s_cloud_data('k0s', 'k0s', 'high', 'k0s_process')
        return true
      end

      false
    end

    def detect_kubernetes_k3d
      return false unless in_kubernetes_pod?

      # K3d is K3s in Docker
      # Check for k3d in hostname or labels
      hostname = inspec.command('hostname').stdout.strip
      if hostname.include?('k3d')
        set_k8s_cloud_data('k3d', 'k3d', 'high', 'hostname')
        return true
      end

      # Check via kubectl
      if has_kubectl?
        node_name = inspec.command('kubectl get node -o jsonpath=\'{.items[0].metadata.name}\' 2>/dev/null').stdout
        if node_name.include?('k3d')
          set_k8s_cloud_data('k3d', 'k3d', 'high', 'node_name')
          return true
        end
      end

      false
    end

    def detect_kubernetes_generic
      return false unless in_kubernetes_pod?

      # Generic Kubernetes detection
      @data[:system] = detect_container_runtime || 'container'
      @data[:role] = 'guest'
      @data[:orchestrator] = 'kubernetes'
      @data[:k8s_distribution] = 'vanilla'
      @data[:confidence] = 'high'
      @data[:detection_method] = 'kubernetes_generic'
      populate_k8s_metadata

      true
    end

    def set_k8s_cloud_data(distribution, cloud, confidence, method)
      @data[:system] = detect_container_runtime || 'container'
      @data[:role] = 'guest'
      @data[:container_runtime] = detect_container_runtime
      @data[:orchestrator] = 'kubernetes'
      @data[:k8s_distribution] = distribution
      @data[:cloud_provider] = cloud if cloud
      @data[:confidence] = confidence
      @data[:detection_method] = method
      populate_k8s_metadata
    end

    def in_kubernetes_pod?
      # Method 1: Service account token (most reliable)
      return true if inspec.file('/var/run/secrets/kubernetes.io/serviceaccount/token').exist?

      # Method 2: Check cgroup for kubepods
      if inspec.file('/proc/self/cgroup').exist?
        cgroup_content = inspec.file('/proc/self/cgroup').content
        return true if cgroup_content =~ /kubepods/
      end

      # Method 4: Check for kubernetes directories
      return true if inspec.file('/var/lib/kubelet').exist?
      return true if inspec.file('/etc/kubernetes').exist?

      false
    end

    def populate_k8s_metadata
      # Get namespace from service account
      if inspec.file('/var/run/secrets/kubernetes.io/serviceaccount/namespace').exist?
        @data[:k8s_namespace] = inspec.file('/var/run/secrets/kubernetes.io/serviceaccount/namespace').content.strip
      end

      # Get pod name from hostname
      @data[:k8s_pod_name] = inspec.command('hostname').stdout.strip

      # Get node name from downward API if mounted
      if inspec.file('/etc/podinfo/node').exist?
        @data[:k8s_node_name] = inspec.file('/etc/podinfo/node').content.strip
      end

      # Get service account
      if inspec.file('/var/run/secrets/kubernetes.io/serviceaccount/service-account').exist?
        @data[:k8s_service_account] = inspec.file('/var/run/secrets/kubernetes.io/serviceaccount/service-account').content.strip
      end
    end

    def detect_container_runtime
      # Check for containerd
      if inspec.command('pgrep containerd').exit_status.zero? ||
         inspec.file('/run/containerd').exist?
        return 'containerd'
      end

      # Check for CRI-O
      if inspec.command('pgrep crio').exit_status.zero? ||
         inspec.file('/var/run/crio').exist?
        return 'cri-o'
      end

      # Check for Docker
      if inspec.file('/.dockerenv').exist? ||
         inspec.file('/.dockerinit').exist? ||
         inspec.command('pgrep dockerd').exit_status.zero?
        return 'docker'
      end

      # Check for Podman
      if inspec.file('/run/podman').exist? ||
         /container=podman/.match?(inspec.file('/proc/1/environ').content)
        return 'podman'
      end

      # Check for runc
      if inspec.command('pgrep runc').exit_status.zero?
        return 'runc'
      end

      nil
    end

    def has_kubectl?
      inspec.command('which kubectl').exit_status.zero?
    end

    #
    # Container Detection Methods
    #

    def detect_docker_compose
      return false unless detect_docker_base

      # Check hostname pattern (Compose sets predictable hostnames)
      hostname = inspec.command('hostname').stdout.strip
      # Compose hostnames are typically: <service>_<number> or just <service>
      # But this isn't reliable enough alone

      # Check for compose-specific network
      if inspec.command('which ip').exit_status.zero?
        routes = inspec.command('ip route show').stdout
        # Compose creates networks like: <project>_default
        if routes =~ /_default/
          @data[:orchestrator] = 'docker-compose'
          @data[:confidence] = 'medium'
          return true
        end
      end

      # Check /proc/1/environ for COMPOSE variables (reliable from inside container)
      if inspec.file('/proc/1/environ').exist?
        environ = inspec.file('/proc/1/environ').content
        if environ.include?('COMPOSE_PROJECT') || environ.include?('COMPOSE_SERVICE')
          @data[:orchestrator] = 'docker-compose'
          @data[:confidence] = 'high'
          return true
        end
      end

      false
    end

    def detect_docker_swarm
      return false unless detect_docker_base

      # Check for swarm-specific indicators
      if inspec.file('/var/lib/docker/swarm').exist?
        @data[:orchestrator] = 'docker-swarm'
        @data[:confidence] = 'high'
        return true
      end

      false
    end

    def detect_nomad
      # Check for Nomad directories (reliable)
      if inspec.file('/opt/nomad').exist? || inspec.file('/etc/nomad.d').exist?
        @data[:orchestrator] = 'nomad'
        @data[:confidence] = 'high'
        return true
      end

      # Check for Nomad process
      if inspec.command('pgrep nomad').exit_status.zero?
        @data[:orchestrator] = 'nomad'
        @data[:confidence] = 'high'
        return true
      end

      # Check for Nomad alloc directory
      if inspec.file('/alloc').exist? && inspec.file('/local').exist? && inspec.file('/secrets').exist?
        @data[:orchestrator] = 'nomad'
        @data[:confidence] = 'medium'
        return true
      end

      false
    end

    def detect_podman
      cgroup_content = inspec.file('/proc/self/cgroup').content if inspec.file('/proc/self/cgroup').exist?
      environ_content = inspec.file('/proc/1/environ').content if inspec.file('/proc/1/environ').exist?

      if /container=podman/.match?(environ_content) || cgroup_content&.include?('podman')
        @data[:system] = 'podman'
        @data[:role] = 'guest'
        @data[:container_runtime] = 'podman'
        @data[:confidence] = 'high'
        @data[:detection_method] = 'podman_environ'
        return true
      end

      false
    end

    def detect_docker
      detect_docker_base
    end

    def detect_docker_base
      # Check for Docker-specific files
      if inspec.file('/.dockerenv').exist? || inspec.file('/.dockerinit').exist?
        @data[:system] = 'docker'
        @data[:role] = 'guest'
        @data[:container_runtime] = 'docker'
        @data[:confidence] = 'high'
        @data[:detection_method] = 'docker_env_file'
        return true
      end

      # Check cgroup
      if inspec.file('/proc/self/cgroup').exist?
        cgroup_content = inspec.file('/proc/self/cgroup').content
        if cgroup_content =~ %r{^\d+:[^:]+:/(lxc/)?docker/.+$}
          @data[:system] = 'docker'
          @data[:role] = 'guest'
          @data[:container_runtime] = 'docker'
          @data[:confidence] = 'high'
          @data[:detection_method] = 'docker_cgroup'
          return true
        end
      end

      false
    end

    def detect_lxc
      return false unless inspec.file('/proc/self/cgroup').exist?

      cgroup_content = inspec.file('/proc/self/cgroup').content

      if cgroup_content =~ %r{^\d+:[^:]+:/lxc/}
        @data[:system] = 'lxc'
        @data[:role] = 'guest'
        @data[:container_runtime] = 'lxc'
        @data[:confidence] = 'high'
        @data[:detection_method] = 'lxc_cgroup'
        return true
      end

      # Check for LXC host
      if inspec.command('which lxc-version').exit_status.zero? && cgroup_content =~ %r{^\d+:[^:]+:/$}
        @data[:system] = 'lxc'
        @data[:role] = 'host'
        @data[:confidence] = 'medium'
        @data[:detection_method] = 'lxc_host'
        return true
      end

      false
    end

    def detect_lxd
      if inspec.file('/dev/lxd/sock').exist?
        @data[:system] = 'lxd'
        @data[:role] = 'guest'
        @data[:confidence] = 'high'
        @data[:detection_method] = 'lxd_socket_guest'
        return true
      elsif inspec.file('/var/lib/lxd/devlxd').exist? || inspec.file('/var/snap/lxd').exist?
        @data[:system] = 'lxd'
        @data[:role] = 'host'
        @data[:confidence] = 'high'
        @data[:detection_method] = 'lxd_host_dir'
        return true
      end

      false
    end

    #
    # Serverless Container Detection
    # NOTE: These are UNTESTED - based on research/documentation
    #

    def detect_ecs_fargate
      # Check for ECS Fargate metadata endpoint
      # UNTESTED - needs validation in actual Fargate environment
      metadata_uri = inspec.command('cat /proc/1/environ 2>/dev/null | tr "\\0" "\\n" | grep ECS_CONTAINER_METADATA_URI').stdout.strip

      if !metadata_uri.empty?
        # Try to query the metadata endpoint
        task_metadata = inspec.command("curl -s #{metadata_uri.split('=')[1]} 2>/dev/null").stdout

        if task_metadata.include?('LaunchType') && task_metadata.include?('FARGATE')
          @data[:system] = 'container'
          @data[:role] = 'guest'
          @data[:orchestrator] = 'ecs'
          @data[:cloud_provider] = 'ecs-fargate'
          @data[:confidence] = 'high'
          @data[:detection_method] = 'fargate_metadata'
          return true
        end
      end

      false
    end

    def detect_cloud_run
      # Check /proc/1/environ for Cloud Run variables
      # UNTESTED - needs validation in actual Cloud Run environment
      if inspec.file('/proc/1/environ').exist?
        environ = inspec.file('/proc/1/environ').content

        # Cloud Run sets K_SERVICE, K_REVISION, K_CONFIGURATION
        if environ.include?('K_SERVICE') && environ.include?('K_REVISION')
          @data[:system] = 'container'
          @data[:role] = 'guest'
          @data[:orchestrator] = 'cloud-run'
          @data[:cloud_provider] = 'gcp-cloud-run'
          @data[:confidence] = 'high'
          @data[:detection_method] = 'cloud_run_environ'
          return true
        end
      end

      false
    end

    def detect_azure_container_instances
      # Check Azure IMDS endpoint
      # UNTESTED - needs validation in actual ACI environment
      metadata = inspec.command('curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null').stdout

      if metadata.include?('compute') && metadata.include?('azureEnvironment')
        # Check if it's ACI (vs Azure VM)
        # ACI has different metadata structure
        if !metadata.include?('vmSize')  # VMs have vmSize, ACI doesn't
          @data[:system] = 'container'
          @data[:role] = 'guest'
          @data[:orchestrator] = 'aci'
          @data[:cloud_provider] = 'azure-aci'
          @data[:confidence] = 'medium'
          @data[:detection_method] = 'aci_metadata'
          return true
        end
      end

      false
    end

    #
    # VM Cloud Provider Detection
    #

    def detect_aws_ec2
      # Check for EC2 metadata service (IMDSv2)
      token = inspec.command('curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null').stdout

      if !token.empty?
        instance_id = inspec.command("curl -s -H \"X-aws-ec2-metadata-token: #{token}\" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null").stdout

        if instance_id.start_with?('i-')
          @data[:system] = 'kvm'  # EC2 uses KVM/Xen
          @data[:role] = 'guest'
          @data[:hypervisor] = 'aws-nitro'  # Modern EC2 uses Nitro
          @data[:vm_cloud_provider] = 'aws-ec2'
          @data[:confidence] = 'high'
          @data[:detection_method] = 'ec2_metadata'
          return true
        end
      end

      # Fallback: Check DMI for EC2
      if inspec.file('/sys/devices/virtual/dmi/id/product_uuid').exist?
        uuid = inspec.file('/sys/devices/virtual/dmi/id/product_uuid').content
        if uuid.downcase.start_with?('ec2')
          @data[:vm_cloud_provider] = 'aws-ec2'
          @data[:confidence] = 'medium'
          return true
        end
      end

      false
    end

    def detect_gcp_gce
      # Check GCP metadata service
      project_id = inspec.command('curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id 2>/dev/null').stdout

      if !project_id.empty? && !project_id.include?('curl')
        @data[:system] = 'kvm'
        @data[:role] = 'guest'
        @data[:hypervisor] = 'gcp-compute'
        @data[:vm_cloud_provider] = 'gcp-gce'
        @data[:confidence] = 'high'
        @data[:detection_method] = 'gce_metadata'
        return true
      end

      # Check DMI
      if inspec.file('/sys/devices/virtual/dmi/id/product_name').exist?
        product = inspec.file('/sys/devices/virtual/dmi/id/product_name').content
        if product.include?('Google') || product.include?('Compute Engine')
          @data[:vm_cloud_provider] = 'gcp-gce'
          @data[:confidence] = 'medium'
          return true
        end
      end

      false
    end

    def detect_azure_vm
      # Check Azure metadata service
      metadata = inspec.command('curl -s -H "Metadata:true" http://169.254.169.254/metadata/instance?api-version=2021-02-01 2>/dev/null').stdout

      if metadata.include?('azureEnvironment')
        @data[:system] = 'hyper-v'
        @data[:role] = 'guest'
        @data[:hypervisor] = 'azure-hypervisor'
        @data[:vm_cloud_provider] = 'azure-vm'
        @data[:confidence] = 'high'
        @data[:detection_method] = 'azure_metadata'
        return true
      end

      # Check for Azure agent
      if inspec.file('/var/lib/waagent').exist?
        @data[:vm_cloud_provider] = 'azure-vm'
        @data[:confidence] = 'medium'
        return true
      end

      false
    end

    def detect_digitalocean
      # Check DigitalOcean metadata service
      droplet_id = inspec.command('curl -s http://169.254.169.254/metadata/v1/id 2>/dev/null').stdout

      if droplet_id.match?(/^\d+$/)
        @data[:system] = 'kvm'
        @data[:role] = 'guest'
        @data[:vm_cloud_provider] = 'digitalocean'
        @data[:confidence] = 'high'
        @data[:detection_method] = 'do_metadata'
        return true
      end

      false
    end

    def detect_utm
      # UTM is QEMU-based macOS virtualization
      # UNTESTED - needs validation on macOS with UTM
      return false unless inspec.os.darwin?

      # Check DMI for QEMU (UTM uses QEMU)
      if inspec.file('/sys/devices/virtual/dmi/id/product_name').exist?
        product = inspec.file('/sys/devices/virtual/dmi/id/product_name').content
        if product.include?('QEMU')
          @data[:system] = 'utm'
          @data[:role] = 'guest'
          @data[:hypervisor] = 'qemu'
          @data[:confidence] = 'medium'
          @data[:detection_method] = 'utm_dmi_qemu'
          return true
        end
      end

      # Check cpuinfo for QEMU
      if inspec.file('/proc/cpuinfo').exist?
        cpuinfo = inspec.file('/proc/cpuinfo').content
        if cpuinfo.include?('QEMU')
          @data[:system] = 'utm'
          @data[:role] = 'guest'
          @data[:hypervisor] = 'qemu'
          @data[:confidence] = 'medium'
          @data[:detection_method] = 'utm_cpuinfo'
          return true
        end
      end

      false
    end

    def detect_colima
      # Colima is a macOS container runtime
      # UNTESTED - needs validation on macOS with Colima
      # Detection from inside a container is difficult since it uses Docker/containerd
      # Best we can do is check for Colima-specific socket locations if mounted

      # Check for Colima Docker socket (if bind-mounted into container)
      if inspec.file('/var/run/docker.sock').exist?
        socket_target = inspec.command('readlink /var/run/docker.sock 2>/dev/null').stdout
        if socket_target.include?('.colima')
          @data[:system] = 'docker'
          @data[:role] = 'guest'
          @data[:container_runtime] = 'docker'
          @data[:cloud_provider] = 'colima'
          @data[:confidence] = 'medium'
          @data[:detection_method] = 'colima_socket'
          return true
        end
      end

      # This is very hard to detect from inside a container
      # Colima doesn't leave obvious markers inside containers
      false
    end

    #
    # Traditional VM Detection (Original Methods Enhanced)
    #

    def detect_xen
      return false unless inspec.file("/proc/xen/capabilities").exist?

      @data[:system] = "xen"
      @data[:hypervisor] = "xen"

      if inspec.file("/proc/xen/capabilities").content =~ /control_d/i
        @data[:role] = "host"
      else
        @data[:role] = "guest"
      end

      @data[:confidence] = 'high'
      @data[:detection_method] = 'xen_capabilities'
      true
    end

    def detect_virtualbox
      return false unless inspec.file("/proc/modules").exist?

      modules = inspec.file("/proc/modules").content

      if modules =~ /^vboxdrv/
        @data[:system] = "vbox"
        @data[:role] = "host"
        @data[:hypervisor] = "virtualbox"
        @data[:confidence] = 'high'
        @data[:detection_method] = 'vbox_module_host'
        return true
      elsif modules =~ /^vboxguest/
        @data[:system] = "vbox"
        @data[:role] = "guest"
        @data[:hypervisor] = "virtualbox"
        @data[:confidence] = 'high'
        @data[:detection_method] = 'vbox_module_guest'
        return true
      end

      # Check DMI for VirtualBox
      if inspec.file('/sys/devices/virtual/dmi/id/product_name').exist?
        product = inspec.file('/sys/devices/virtual/dmi/id/product_name').content
        if product.include?('VirtualBox')
          @data[:system] = 'vbox'
          @data[:role] = 'guest'
          @data[:hypervisor] = 'virtualbox'
          @data[:confidence] = 'high'
          @data[:detection_method] = 'vbox_dmi'
          return true
        end
      end

      false
    end

    def detect_kvm
      # Check from cpuinfo first
      if inspec.file("/proc/cpuinfo").exist?
        cpuinfo = inspec.file("/proc/cpuinfo").content
        if cpuinfo =~ /QEMU Virtual CPU|Common KVM processor|Common 32-bit KVM processor/
          @data[:system] = "kvm"
          @data[:role] = "guest"
          @data[:hypervisor] = "kvm"
          @data[:confidence] = 'high'
          @data[:detection_method] = 'kvm_cpuinfo'
          return true
        end
      end

      # Check from /sys
      if inspec.file("/sys/devices/virtual/misc/kvm").exist?
        @data[:system] = "kvm"
        @data[:hypervisor] = "kvm"

        if inspec.file("/proc/cpuinfo").content =~ /hypervisor/
          @data[:role] = "guest"
        else
          @data[:role] = "host"
        end

        @data[:confidence] = 'high'
        @data[:detection_method] = 'kvm_sys'
        return true
      end

      false
    end

    def detect_vmware
      return false unless inspec.file("/sys/devices/virtual/dmi/id/product_name").exist?

      product_name = inspec.file("/sys/devices/virtual/dmi/id/product_name").content

      if product_name =~ /^VMware/
        @data[:system] = "vmware"
        @data[:role] = "guest"
        @data[:hypervisor] = "vmware-esxi"
        @data[:confidence] = 'high'
        @data[:detection_method] = 'vmware_dmi'

        # Check if on VMware Cloud (AWS/Azure/GCP)
        detect_vmware_cloud_provider

        return true
      end

      false
    end

    def detect_vmware_cloud_provider
      # VMware Cloud on AWS
      if inspec.command('curl -s http://169.254.169.254/latest/meta-data/ 2>/dev/null').stdout.include?('ami-id')
        @data[:vm_cloud_provider] = 'vmware-cloud-aws'
      end
    end

    def detect_hyper_v
      return false unless inspec.file("/sys/devices/virtual/dmi/id/product_name").exist?

      product_name = inspec.file("/sys/devices/virtual/dmi/id/product_name").content.strip

      if product_name == "Virtual Machine"
        @data[:system] = "hyper-v"
        @data[:role] = "guest"
        @data[:hypervisor] = "hyper-v"
        @data[:confidence] = 'high'
        @data[:detection_method] = 'hyperv_dmi'
        return true
      end

      false
    end

    def detect_parallels
      return false unless inspec.file("/proc/bus/pci/devices").exist?
      return false unless inspec.file("/proc/bus/pci/devices").content =~ /1ab84000/

      @data[:system] = "parallels"
      @data[:role] = "guest"
      @data[:hypervisor] = "parallels"
      @data[:confidence] = 'high'
      @data[:detection_method] = 'parallels_pci'
      true
    end

    def detect_openvz
      if inspec.file("/proc/bc/0").exist?
        @data[:system] = "openvz"
        @data[:role] = "host"
        @data[:confidence] = 'high'
        @data[:detection_method] = 'openvz_bc'
        return true
      elsif inspec.file("/proc/vz").exist?
        @data[:system] = "openvz"
        @data[:role] = "guest"
        @data[:confidence] = 'high'
        @data[:detection_method] = 'openvz_vz'
        return true
      end

      false
    end

    def detect_linux_vserver
      return false unless inspec.file("/proc/self/status").exist?

      proc_self_status = inspec.file("/proc/self/status").content
      vxid = proc_self_status.match(/^(s_context|VxID):\s*(\d+)$/)
      return false unless vxid && vxid[2]

      @data[:system] = "linux-vserver"
      @data[:role] = vxid[2] == "0" ? "host" : "guest"
      @data[:confidence] = 'high'
      @data[:detection_method] = 'vserver_vxid'
      true
    end

    #
    # Windows Detection
    #

    def detect_windows
      return unless inspec.os.windows?

      wmi_data = windows_computer_system
      return unless wmi_data

      model = wmi_data["Model"]
      manufacturer = wmi_data["Manufacturer"]

      case model
      when "Virtual Machine"
        @data[:system] = "hyper-v"
        @data[:hypervisor] = "hyper-v"
      when /^VMware/
        @data[:system] = "vmware"
        @data[:hypervisor] = "vmware-esxi"
      when "VirtualBox"
        @data[:system] = "vbox"
        @data[:hypervisor] = "virtualbox"
      end

      case manufacturer
      when "Xen"
        @data[:system] = "xen"
        @data[:hypervisor] = "xen"
      when "QEMU"
        @data[:system] = "kvm"
        @data[:hypervisor] = "kvm"
      end

      if @data[:system]
        @data[:role] = "guest"
        @data[:confidence] = 'high'
        @data[:detection_method] = 'windows_wmi'
      end
    end

    def windows_computer_system
      script = "Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop | ConvertTo-Json"
      cmd = inspec.powershell(script)
      JSON.parse(cmd.stdout)
    rescue JSON::ParserError, StandardError
      nil
    end
  end
end
