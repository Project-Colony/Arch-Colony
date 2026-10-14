# shellcheck shell=bash disable=SC2034
# colonyctl's text, in English. English is canonical; fr.sh holds the same keys,
# and tools/check-i18n.py fails CI when they differ.
#
# Plain double-quoted assignments: no $, no backquotes. A value used as a printf
# format says so; its %s are filled in the order the comment gives. Command
# names, options and package names stay as they are typed.

msg_usage_title="Arch Colony system control"
msg_usage_update="update the system (pacman -Syu)"
msg_usage_status="what this machine is running, and what is protecting it"
msg_usage_firewall="Colony Firewall Control (cfc); changes need sudo"
msg_usage_note="pacman still works, and is not going anywhere. This is a front door, not a
gate: [colony] is an ordinary pacman repository."

msg_no_sudo="not root and sudo is not installed"
# printf format: the option, then the program name.
msg_pacman_option="%s is pacman's grammar, not this tool's. Use '%s update', or pacman directly."
# printf format: the option, then the program name.
msg_unknown_option="unknown option '%s' - see '%s help'"
msg_aur_needs_paru="--aur needs paru: colonyctl update, then pacman -S paru"
msg_no_firewall="colony-firewall-control is not installed"
# printf format: the argument, then the program name.
msg_pacman_verb="'%s' looks like pacman's grammar. This tool takes verbs - see '%s help'."
# printf format: the command, then the program name.
msg_unknown_command="unknown command '%s' - see '%s help'"

msg_section_system="system"
msg_section_packages="packages"
msg_section_enforcement="enforcement"
msg_section_session="session"
msg_section_firewall="firewall"

msg_distribution="distribution"
msg_kernel="kernel"
msg_configured="configured"
msg_server="server"
msg_db_signature="database signature"
msg_required="required"
msg_not_required="not required - add 'SigLevel = Required DatabaseRequired' under [colony] in /etc/pacman.conf"
msg_not_configured="not configured - Colony packages will not update"
msg_installed="installed"
# printf format: the number of installed packages.
msg_package_count="%s packages"
msg_kernel_lsms="kernel LSMs"
msg_active="active"
msg_not_active="not active"
msg_default_target="default target"
msg_no_greeter_will_start="no greeter will start"
msg_unknown="unknown"
msg_display_manager="display manager"
# printf format: the display manager's unit.
msg_dm_running="%s, running"
# printf format: the display manager's unit.
msg_dm_not_running="%s, enabled but not running"
msg_dm_none="none enabled - the machine boots to a console"
msg_greeters_installed="greeters installed"
msg_none="none"
msg_failed_units="failed units"
msg_firewall_not_installed="not installed - pacman -S colony-firewall-defaults"
msg_daemon="daemon"
msg_running="running"
msg_stopped="stopped"
msg_filtering_table="filtering table"
msg_not_loaded="not loaded"
msg_loaded="loaded"
msg_loaded_no_daemon="loaded, no daemon - new connections are refused"
msg_kernel_object="kernel object"
msg_present="present"
msg_missing_object="missing - enforcement cannot outlive the daemon"
