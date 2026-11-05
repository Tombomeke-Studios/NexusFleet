# A stand-in for a fresh Ubuntu VM, for experiment E1: an OpenSSH server and a user "fleet" that logs in
# with an SSH key only and may use sudo without a password (the target-host requirement of NexusFleet).
# Build with WITH_PWSH=true to also install PowerShell and the sshd subsystem PowerShell remoting needs.
FROM ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

ARG PUBKEY
ARG WITH_PWSH=false

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server sudo ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd

# Key-only user with passwordless sudo. Password '*' = no password login, but not a locked account.
RUN useradd --create-home --shell /bin/bash fleet \
    && usermod --password '*' fleet \
    && echo 'fleet ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/fleet \
    && chmod 440 /etc/sudoers.d/fleet \
    && mkdir -p /home/fleet/.ssh \
    && echo "$PUBKEY" > /home/fleet/.ssh/authorized_keys \
    && chown -R fleet:fleet /home/fleet/.ssh \
    && chmod 700 /home/fleet/.ssh \
    && chmod 600 /home/fleet/.ssh/authorized_keys \
    && sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Only for PowerShell remoting over SSH: install pwsh and register it as an sshd subsystem.
RUN if [ "$WITH_PWSH" = "true" ]; then \
        curl -fsSL -o /tmp/ms.deb https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
        && dpkg -i /tmp/ms.deb && rm /tmp/ms.deb \
        && apt-get update && apt-get install -y --no-install-recommends powershell \
        && rm -rf /var/lib/apt/lists/* \
        && echo 'Subsystem powershell /usr/bin/pwsh -sshs -NoLogo' >> /etc/ssh/sshd_config; \
    fi

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
