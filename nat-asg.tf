######################################################################
# ENI Creation
##
resource "aws_network_interface" "nat" {
    count             = "${var.number_of_nats}"

    subnet_id         = "${element(split(",",var.pub_subnet_ids), count.index)}"

    # Let's assign .10 as our internal NAT IP
    private_ips       = [ "${cidrhost(element(split(",",var.pub_subnet_cidrs) , count.index), count.index + 10)}" ]
    security_groups   = [ "${var.nat_sg}" ]
    source_dest_check = false
    tags              {
                        "Name"    = "${var.env}-nat-eni-${count.index}"
                        "owner"   = "${var.owner}"
                        "email"   = "${var.email}"
                        "group"   = "${var.group}"
                        "env"     = "${var.env}"
                      }


}
output "nat_eni_ids" {
  value = "${join(",", aws_network_interface.nat.*.id)}"
}
output "nat_eni_ips" {
  value = "${join(",", aws_network_interface.nat.*.private_ips)}"
}

######################################################################
# EIP Creation
##
resource "aws_eip" "nat" {
    vpc               = true
    count             = "${var.number_of_nats}"
    depends_on        = [ "aws_network_interface.nat" ]
    network_interface = "${element(aws_network_interface.nat.*.id, count.index)}"
}

output "nat_eip_private_ip" {
  value = "${ join(",", aws_eip.nat.*.private_ip) }"
}
output "nat_eip_public_ip" {
  value = "${ join(",", aws_eip.nat.*.public_ip) }"
}
output "nat_eip_instance_id" {
  value = "${ join(",", aws_eip.nat.*.instance) }"
}
output "nat_eip_network_interface_id" {
  value = "${ join(",", aws_eip.nat.*.network_interface) }"
}

######################################################################
# Launch Configuration
##
resource "aws_launch_configuration" "nat_conf" {
    count                = "${var.number_of_nats}"
    name                 = "${var.env}_nat_launch_config_${count.index}"
    depends_on           = ["aws_iam_role.attach_nat_eni_role",
                            "aws_iam_role_policy.attach_nat_eni_policy",
                            "aws_iam_instance_profile.instance_eni_profile"
                           ]
    iam_instance_profile = "${aws_iam_instance_profile.instance_eni_profile.arn}"

    ######################################################################
    # This is required to be able to associate the instance with a
    # public IP. You end up with 2 different public IPs, one of which
    # is a static EIP. The user-data *should* shut down eth0. And the
    # other public IP (the non-EIP one) is not functional at this
    # point.
    associate_public_ip_address = true

    image_id                  = "${var.nat_ami}"
    instance_type             = "${var.nat_instance_type}"
    key_name                  = "${var.aws_key_name}"
    security_groups           = [ "${var.nat_sg}" ]
    # lifecycle {
    #   create_before_destroy = true
    # }
    user_data = <<EOF
#!/bin/bash
echo "${element(aws_network_interface.nat.*.id, count.index)}" > /var/tmp/eni-id.txt
/usr/local/bin/attach_eth1_eni.sh
sleep 60
ifdown eth0
iptables -t nat -A POSTROUTING -j MASQUERADE
iptables -A FORWARD -j ACCEPT
echo 1 > /proc/sys/net/ipv4/conf/all/forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
EOF
}

output "nat_launch_configuration_ids" {
  value = "${join(",", aws_launch_configuration.nat_conf.*.id)}"
}

######################################################################
# ASG Creation
##
resource "aws_autoscaling_group" "nat_asg" {
    count                   = "${var.number_of_nats}"
    name                    = "${var.env}-nat-asg-${count.index}"
    depends_on              = [
                               "aws_launch_configuration.nat_conf",
                               "aws_eip.nat",
                               "aws_network_interface.nat"
                              ]
    launch_configuration    = "${element(aws_launch_configuration.nat_conf.*.name, count.index)}"
    availability_zones      = ["${element(split(",", var.availability_zones), count.index)}"]
    vpc_zone_identifier     = ["${element(split(",",var.pub_subnet_ids), count.index)}"]
    min_size = 1
    max_size = 1
    desired_capacity = 1
    health_check_grace_period = 600
    health_check_type         = "EC2"
    tag {
      key                 = "Name"
      value               = "${var.env}-nat_asg"
      propagate_at_launch = true
    }
    tag {
      key                 = "owner"
      value               = "${var.owner}"
      propagate_at_launch = true
    }
    tag {
      key                 = "email"
      value               = "${var.email}"
      propagate_at_launch = true
    }
    tag {
      key                 = "group"
      value               = "${var.group}"
      propagate_at_launch = true
    }
    tag {
      key                 = "env"
      value               = "${var.env}"
      propagate_at_launch = true
    }
}

output "asg_id" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.id) }"
}

output "asg_availability_zones" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.availability_zones) }"
}

output "asg_min_size" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.min_size) }"
}

output "asg_max_size" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.max_size) }"
}

output "asg_default_cooldown" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.default_cooldown) }"
}

output "asg_name" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.name) }"
}

output "asg_health_check_grace_period" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.health_check_grace_period) }"
}

output "asg_health_check_type" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.health_check_type) }"
}

output "asg_desired_capacity" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.desired_capacity) }"
}

output "asg_launch_configuration" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.launch_configuration) }"
}

output "asg_vpc_zone_identifier" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.vpc_zone_identifier) }"
}

output "asg_load_balancers" {
  value = "${ join(",",aws_autoscaling_group.nat_asg.*.load_balancers) }"
}


######################################################################
# Policies/Roles
##

## IAM Role
resource "aws_iam_role" "attach_nat_eni_role" {
    name               = "${var.env}_NAT_ENI_role"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

output "aws_nat_eni_iam_role_id" {
  value = "${aws_iam_role.attach_nat_eni_role.unique_id}"
}
output "aws_nat_eni_iam_role_arn" {
  value = "${aws_iam_role.attach_nat_eni_role.arn}"
}


## IAM Role Policy
resource "aws_iam_role_policy" "attach_nat_eni_policy" {
    name = "${var.env}_NAT_ENI_policy"
    role = "${aws_iam_role.attach_nat_eni_role.id}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:AttachNetworkInterface",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyNetworkInterfaceAttribute"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}


output "nat_attach_eni_policy_id" {
  value = "${aws_iam_role_policy.attach_nat_eni_policy.id}"
}
output "nat_attach_eni_policy_name" {
  value = "${aws_iam_role_policy.attach_nat_eni_policy.name}"
}
output "nat_attach_eni_policy_policy" {
  value = "${aws_iam_role_policy.attach_nat_eni_policy.policy}"
}

output "nat_attach_eni_policy_role" {
  value = "${aws_iam_role_policy.attach_nat_eni_policy.role}"
}

## IAM Instance profile
resource "aws_iam_instance_profile" "instance_eni_profile" {
    name  = "${var.env}_attach_eni_instance_profile"
    roles = ["${aws_iam_role.attach_nat_eni_role.id}"]
}

output "attach_eni_profile_instance_id" {
  value = "${aws_iam_instance_profile.instance_eni_profile.id}"
}

output "attach_eni_profile_arn" {
  value = "${aws_iam_instance_profile.instance_eni_profile.arn}"
}
output "attach_eni_profile_create_date" {
  value = "${aws_iam_instance_profile.instance_eni_profile.create_date}"
}
output "attach_eni_profile_name" {
  value = "${aws_iam_instance_profile.instance_eni_profile.name}"
}
output "attach_eni_profile_path" {
  value = "${aws_iam_instance_profile.instance_eni_profile.path}"
}
output "attach_eni_profile_roles" {
  value = "${aws_iam_instance_profile.instance_eni_profile.roles}"
}
output "attach_eni_profile_unique_id" {
  value = "${aws_iam_instance_profile.instance_eni_profile.unique_id}"
}
