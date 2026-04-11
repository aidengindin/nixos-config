{ ... }:
{
  boot.kernel.sysctl = {
    # Restrict kernel pointer and address leaks to root only
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.perf_event_paranoid" = 2;

    # Disable unprivileged eBPF and harden JIT (significant kernel attack surface)
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;

    # Restrict ptrace to parent/child relationships only
    "kernel.yama.ptrace_scope" = 1;

    # Prevent core dumps from setuid binaries
    "fs.suid_dumpable" = 0;

    # Disable magic SysRq key
    "kernel.sysrq" = 0;

    # Network hardening
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_rfc1337" = 1;

    # Prevent NULL pointer dereference exploits
    "vm.mmap_min_addr" = 65536;
  };
}
