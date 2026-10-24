require "helper"
require "inspec/resource"
require "inspec/resources/file"
require "inspec/resources/virtualization"
require "digest"
require "ostruct"
require "train"
require "train/transports/mock"

$cmds = []
module CmdTrace
  def run_command_via_connection(cmd, &blk)
    $cmds << cmd
    super
  end
end
Train::Transports::Mock::Connection.prepend(CmdTrace)

def file_proc(files)
  proc { |path| OpenStruct.new(exist?: files.key?(path), content: files[path]) }
end

def run(name, os: :ubuntu, files: {}, cmds: {})
  $cmds = []
  ml = MockLoader.new(os)
  conn = ml.backend.backend
  cmds.each do |c, (out, code)|
    s = Train::Transports::Mock::Connection::Command.new(out, "", code)
    conn.commands[c] = s
    conn.commands[Digest::SHA256.hexdigest(c)] = s
  end
  ml.backend.stub :file, file_proc(files) do
    begin
      r = ml.load_resource("virtualization")
      extra = %i{orchestrator k8s_distribution cloud_provider container_runtime hypervisor}.select { |m| r.respond_to?(m) }
        .map { |m| "#{m}=#{r.send(m).inspect}" }.join(" ")
      puts format("%-34s system=%-14s role=%-6s rid=%-16s physical?=%-5s virtual?=%-5s %s",
        name, r.system.inspect, r.role.inspect, r.resource_id.inspect, r.physical_system?.inspect, r.virtual_system?.inspect, extra)
    rescue => e
      puts format("%-34s RAISED %s: %s", name, e.class, e.message[0, 60])
    end
  end
  nets = $cmds.select { |c| c =~ /curl|metadata/ }
  puts format("%-34s   commands run: %d (network: %d) %s", "", $cmds.size, nets.size, ENV["SHOWCMDS"] ? $cmds.inspect : "")
end

DOCKERENV = { "/.dockerenv" => "" }
run "S0 nothing detected"
run "S1 docker /.dockerenv", files: DOCKERENV
run "S2 docker systemd cgroup, no .dockerenv", files: { "/proc/self/cgroup" => "12:pids:/system.slice/docker-abc123def.scope\n" }
run "S2b lxc systemd cgroup", files: { "/proc/self/cgroup" => "12:pids:/system.slice/lxc-web1.scope\n" }
run "S3 k8s pod (kubepods cgroup)", files: { "/proc/self/cgroup" => "1:name=systemd:/kubepods/besteffort/pod123/abc\n",
                                            "/var/run/secrets/kubernetes.io/serviceaccount/token" => "x",
                                            "/var/run/secrets/kubernetes.io/serviceaccount/namespace" => "default\n" }
run "S3b k8s pod on docker (.dockerenv)", files: { "/proc/self/cgroup" => "1:name=systemd:/kubepods/besteffort/pod123/abc\n", "/.dockerenv" => "" }
run "S4 podman environ", files: { "/proc/self/cgroup" => "", "/proc/1/environ" => "PATH=/binTERM=xtermcontainer=podmanHOME=/root" }
run "S5 lxc cgroup /lxc/", files: { "/proc/self/cgroup" => "3:cpu:/lxc/web1\n" }
run "S6 lxd guest sock", files: { "/dev/lxd/sock" => "" }
run "S6b vmware guest + lxd snap dir", files: { "/sys/devices/virtual/dmi/id/product_name" => "VMware Virtual Platform\n", "/var/snap/lxd" => "" }
run "S7 xen guest", files: { "/proc/xen/capabilities" => "" }
run "S7b xen host", files: { "/proc/xen/capabilities" => "control_d\n" }
run "S8 vbox host + kvm module", files: { "/proc/modules" => "vboxdrv 1 0\nkvm 1 0\n", "/sys/devices/virtual/misc/kvm" => "", "/proc/cpuinfo" => "flags: fpu vme\n" }
run "S8b vbox guest (vboxguest)", files: { "/proc/modules" => "vboxguest 1 0\n" }
run "S9 kvm guest cpuinfo", files: { "/proc/cpuinfo" => "model name : QEMU Virtual CPU version 2.5+\n" }
run "S10 kvm host /sys kvm", files: { "/sys/devices/virtual/misc/kvm" => "", "/proc/cpuinfo" => "flags: fpu vme\n" }
run "S11 vmware guest", files: { "/sys/devices/virtual/dmi/id/product_name" => "VMware Virtual Platform\n" }
run "S12 hyper-v guest", files: { "/sys/devices/virtual/dmi/id/product_name" => "Virtual Machine\n" }
run "S13 openvz guest", files: { "/proc/vz" => "" }
run "S13b openvz host", files: { "/proc/bc/0" => "" }
run "S14 parallels", files: { "/proc/bus/pci/devices" => "0000 1ab84000 ...\n" }
run "S15 linux-vserver guest", files: { "/proc/self/status" => "Name: bash\nVxID: 42\n" }
run "S17 nomad client host on vmware", files: { "/etc/nomad.d" => "", "/sys/devices/virtual/dmi/id/product_name" => "VMware Virtual Platform\n" }
run "S18 azure vm, IMDS blocked", files: { "/sys/devices/virtual/dmi/id/product_name" => "Virtual Machine\n", "/var/lib/waagent" => "" }
run "S18b gce vm, metadata blocked", files: { "/sys/devices/virtual/dmi/id/product_name" => "Google Compute Engine\n" }
TOK = 'curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null'
IID = 'curl -s -H "X-aws-ec2-metadata-token: TOKEN123" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null'
run "S19 EC2 xen-gen instance", files: { "/proc/xen/capabilities" => "" }, cmds: { TOK => ["TOKEN123", 0], IID => ["i-0abc", 0] }
run "S19b EC2 IMDS blocked, product_uuid", files: { "/sys/devices/virtual/dmi/id/product_uuid" => "EC2A1B2C-...\n" }
run "S20 k8s node host on kvm guest", files: { "/etc/kubernetes" => "", "/var/lib/kubelet" => "", "/run/containerd" => "",
                                               "/proc/cpuinfo" => "model name : QEMU Virtual CPU version 2.5+\n" }
run "S20b k3s node host, bare metal", files: { "/etc/kubernetes" => "", "/var/lib/rancher/k3s" => "", "/run/containerd" => "" }
run "S21 EC2 nitro, otherwise undetectable", cmds: { TOK => ["TOKEN123", 0], IID => ["i-0abc", 0] }
WMI = "Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop | ConvertTo-Json"
run "W1 windows VirtualBox", os: :windows, cmds: { WMI => ['{"Model":"VirtualBox","Manufacturer":"innotek GmbH"}', 0] }
run "W2 windows Xen HVM domU", os: :windows, cmds: { WMI => ['{"Model":"HVM domU","Manufacturer":"Xen"}', 0] }
run "W3 windows QEMU/KVM", os: :windows, cmds: { WMI => ['{"Model":"Standard PC (Q35)","Manufacturer":"QEMU"}', 0] }
run "W4 windows Hyper-V", os: :windows, cmds: { WMI => ['{"Model":"Virtual Machine","Manufacturer":"Microsoft Corporation"}', 0] }
run "W5 windows physical Dell", os: :windows, cmds: { WMI => ['{"Model":"OptiPlex","Manufacturer":"Dell Inc."}', 0] }
run "W6 windows WMI fails", os: :windows
