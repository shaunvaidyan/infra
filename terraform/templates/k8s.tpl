[all:vars]
ansible_become=yes
ansible_become_method=sudo
ansible_python_interpreter='/usr/bin/env python3'

[master]
${k3s_master_ip}

[node]
${k3s_node_ip}

[k3s_cluster:children]
master
node