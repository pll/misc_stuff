# misc_stuff

Miscellaneous stuff I want to share with the world.


- nat-asg.tf: Terraform code to create a 1:1 ASG for NATs
- attach_eth1_eni.sh : Script exec'ed via the user_data field in nat-asg.tf

attach_eth1_eni.sh should be baked into an AMI which is then used
specifically for your NATS. Essentially, it just pegs the eth1
interface at a static IP address, then associates a previously created
EIP with eth1.  The user_data then waits for this script to complete,
then downs eth0 and updates iptables.

