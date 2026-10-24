# Test Enhanced Virtualization Resource

control 'virtualization-detection' do
  title 'Test virtualization detection capabilities'

  describe virtualization do
    it { should_not be_physical }
    its('system') { should_not be_nil }
    its('role') { should eq 'guest' }
  end
end

control 'container-detection' do
  title 'Test container detection'

  describe virtualization do
    it { should be_container }
    its('container_runtime') { should_not be_nil }
  end
end

control 'kubernetes-detection' do
  title 'Test Kubernetes detection'

  describe virtualization do
    it { should be_kubernetes }
    its('orchestrator') { should eq 'kubernetes' }
    its('k8s_namespace') { should_not be_nil }
    its('k8s_pod_name') { should_not be_nil }
  end
end

control 'cloud-provider-detection' do
  title 'Test cloud provider detection'

  describe virtualization do
    its('cloud_provider') { should_not be_nil }
    its('k8s_distribution') { should_not be_nil }
  end
end

control 'metadata-richness' do
  title 'Test rich metadata'

  describe 'virtualization metadata' do
    subject { virtualization.metadata }

    its([:system]) { should_not be_nil }
    its([:role]) { should_not be_nil }
    its([:orchestrator]) { should_not be_nil }
    its([:confidence]) { should_not be_nil }
    its([:detection_method]) { should_not be_nil }
  end
end
