resource "aws_network_interface" "nat" {
    subnet_id         = "${var.pub1_id}"
    # Let's assign .10 as our internal NAT IP
    private_ips       = ["${cidrhost(var.pub1_cidr,10)}"]
    security_groups   = [ "${var.nat_sg}" ]       
    source_dest_check = false 
    tags              {
                        "Name"    = "${var.env}-nat-eni"
                        "owner"   = "${var.owner}"
                        "email"   = "${var.email}"
                        "group"   = "${var.group}"
                        "env"     = "${var.env}"
                      }


}
output "nat_eni_id" {
  value = "${aws_network_interface.nat.id}"
}


resource "aws_eip" "nat" {
    vpc               = true
    depends_on        = [ "aws_network_interface.nat" ]
    network_interface = "${aws_network_interface.nat.id}"
}


resource "aws_launch_configuration" "nat_conf" {
    name                        = "${var.env}_nat_launch_config"
    depends_on                  = ["aws_iam_role.attach_nat_eni_role",
    				   "aws_iam_role_policy.attach_nat_eni_policy",
				   "aws_iam_instance_profile.instance_attach_eni_profile"
    				  ]
    iam_instance_profile        = "${aws_iam_instance_profile.instance_attach_eni_profile.arn}"

    ######################################################################
    # This is required to be able to associate the instance with a
    # public IP. You end up with 2 different public IPs, one of which
    # is a static EIP. The user-data *should* shut down eth0. And the
    # other public IP (the non-EIP one) is not functional at this
    # point.
    associate_public_ip_address = true

    image_id                    = "${var.nat_ami}"
    instance_type               = "${var.nat_instance_size"}
    key_name                    = "${var.aws_key_name}"
    security_groups             = [ "${var.nat_sg}" ]
    # lifecycle {
    #   create_before_destroy = true
    # }
    user_data = <<EOF
#!/bin/bash
echo "${aws_network_interface.nat.id}" > /var/tmp/eni-id.txt
/usr/local/bin/attach_eth1_eni.sh
sleep 60
ifdown eth0
iptables -t nat -A POSTROUTING -j MASQUERADE
iptables -A FORWARD -j ACCEPT
echo 1 > /proc/sys/net/ipv4/conf/all/forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
EOF
}

resource "aws_autoscaling_group" "nat_asg" {
    name                    = "nat-asg"
    depends_on              = [
    			       "aws_launch_configuration.nat_conf",
			       "aws_eip.nat",
			       "aws_network_interface.nat"
    			      ]
    launch_configuration    = "${aws_launch_configuration.nat_conf.name}"
    # lifecycle {
    #   create_before_destroy = true
    # }
    availability_zones      = ["${var.zone0}"]
    vpc_zone_identifier      = ["${var.pub1_id}"]
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



######################################################################
# Policies/Roles
##
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

resource "aws_iam_instance_profile" "instance_attach_eni_profile" {
    name  = "${var.env}_attach_eni_instance_profile"
    roles = ["${aws_iam_role.attach_nat_eni_role.id}"]
}
