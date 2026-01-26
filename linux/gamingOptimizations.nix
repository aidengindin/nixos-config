{ config, lib, ... }:

let
  cfg = config.agindin.gamingOptimizations;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.agindin.gamingOptimizations = {
    enable = mkEnableOption "Whether to enable optimizations for gaming.";
    amd.enable = mkEnableOption "Whether to enable optimizations specific to AMD GPUs.";
  };

  config = mkIf cfg.enable {

    # Use the performance CPU governor
    services.power-profiles-daemon.enable = false;
    services.tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_BAT = "schedutil";
        CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "performance";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      };
    };

    services.udev.extraRules = ''
      # NVMe - no scheduler needed, hardware handles it
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
      # SATA SSDs - kyber is good here
      ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"
      # eMMC - kyber
      ACTION=="add|change", KERNEL=="mmcblk[0-9]*", ATTR{queue/scheduler}="kyber"
    '';

    boot.kernelParams = [
      # Scheduler optimizations
      "preempt=full"

      # Reduce input latency
      "usbhid.mousepoll=1"

      # Memory management for gaming
      "vm.max_map_count=2147483642"

      "split_lock_detect=off"
    ]
    ++ (
      if cfg.amd.enable then
        [
          # Enable all GPU features including overclocking
          "amdgpu.ppfeaturemask=0xffffffff"

          # Use AMD P-State driver for better CPU scaling
          "amd_pstate=active"
        ]
      else
        [ ]
    );

    boot.kernel.sysctl = {
      # Lower swappiness
      "vm.swappiness" = 10;

      # Disable memory compaction
      "vm.compaction_proactiveness" = 0;

      # Increase dirty page writeback time for better performance
      "vm.dirty_ratio" = 10;
      "vm.dirty_background_ratio" = 5;

      # Network latency for online gaming
      "net.ipv4.tcp_fastopen" = 3;
      "net.core.netdev_max_backlog" = 16384;

      # Not really sure what this does tbh, see cryoutilities
      "vm.page_lock_unfairness" = 1;

      # THP - use madvise instead of always to avoid allocation stalls
      "vm.transparent_hugepage" = "madvise";
    };

    systemd.tmpfiles.rules = [
      # Enable THP for shared memory when requested
      "w /sys/kernel/mm/transparent_hugepage/shmem_enabled - - - - advise"
      # Disable hugepage defragmentation to avoid stalls
      "w /sys/kernel/mm/transparent_hugepage/khugepaged/defrag - - - - 0"
    ];
  };
}
