# Build a Kubernetes (k3s) cluster on Proxmox with Ansible and Terraform


## System requirements

* Ansible 2.4.0+
* Terraform
* Proxmox


### Proxmox setup

This setup relies on cloud-init images. I connected to a preexiting Ubuntu VM running on my Proxmox machine and ran the following to install image tooling on the server:


```bash
apt-get install libguestfs-tools
```

Get the image that you would like to work with.
you can browse to <https://cloud-images.ubuntu.com> and select any other version that you would like to work with.

```bash
wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
```

Update the image and install Proxmox agent for Terraform to work properly.


```bash
virt-customize focal-server-cloudimg-amd64.img --install qemu-guest-agent
```

now that we have the image, we need to move it to the Proxmox server.
I used `scp`

```bash
scp focal-server-cloudimg-amd64.img Proxmox_username@Proxmox_host:/path_on_Proxmox/focal-server-cloudimg-amd64.img
```

so now we should have the image configured and on our Proxmox server. let's start creating the VM

```bash
qm create 9000 --name "ubuntu-focal-cloudinit-template" --memory 2048 --net0 virtio,bridge=vmbr0
```

for ubuntu images, rename the image suffix

```bash
mv focal-server-cloudimg-amd64.img focal-server-cloudimg-amd64.qcow2
```

import the disk to the VM

```bash
qm importdisk 9000 focal-server-cloudimg-amd64.qcow2 local-lvm
```

configure the VM to use the new image

```bash
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
```

add cloud-init image to the VM

```bash
qm set 9000 --ide2 local-lvm:cloudinit
```

set the VM to boot from the cloud-init disk:

```bash
qm set 9000 --boot c --bootdisk scsi0
```

update the serial on the VM

```bash
qm set 9000 --serial0 socket --vga serial0
```

Now we can configure our base config for the image.
Go to the Proxmox web GUI, go to your VM and look on the cloud-init tab. Here you will find the user name, password, and ssh public key so we can connect to the VM later using Ansible and terraform.
Update the variables and click on `Regenerate Image`

Now convert the VM to a template using:

```bash
qm template 9000
```

### Terraform setup

Terraform file also creates a dynamic host file for Ansible, so we need to create the files first

```bash
cp -R inventory/sample inventory/my-cluster
```

Rename the file `terraform/variables.tfvars.sample` to `terraform/variables.tfvars` and update all the vars.
there you can select how many nodes would you like to have on your cluster and configure the name of the base image. its also importent to update the ssh key that is going to be used and proxmox host address.
to run the Terrafom, you will need to cd into `terraform` and run:

```bash
cd terraform/
terraform init
terraform plan --var-file=variables.tfvars
terraform apply --var-file=variables.tfvars
```
Now wait as Proxmox creates the VMs.


### Ansible setup

First, update the var file in `inventory/my-cluster/group_vars/all.yml` and update the ```ansible_user``` that you're selected in the cloud-init setup. you can also choose if you wold like to install metallb and argocd. if you are installing metallb, you should also specified an ip range for metallb. 

if you are running multiple clusters in your kubeconfig file, make sure to disable ```copy_kubeconfig```.

After you run Terraform, your file should look something like this:

```bash
[master]
192.168.3.200 Ansible_ssh_private_key_file=~/.ssh/proxk3s

[node]
192.168.3.202 Ansible_ssh_private_key_file=~/.ssh/proxk3s
192.168.3.201 Ansible_ssh_private_key_file=~/.ssh/proxk3s
192.168.3.198 Ansible_ssh_private_key_file=~/.ssh/proxk3s
192.168.3.203 Ansible_ssh_private_key_file=~/.ssh/proxk3s

[k3s_cluster:children]
master
node
```

Start provisioning the cluster using the following command:

```bash
# cd to the project root folder and run the playbook
cd ..

ansible-playbook -i inventory/my-cluster/hosts.ini site.yml
```

After a few mins, a K3s cluster should be up and running.

### Kubeconfig

Ansible already copied the file to ~/.kube/config
```bash
scp debian@master_ip:~/.kube/config ~/.kube/config
```

### Argocd
To get argocd initial password run the following:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```
