provider "aws" {
  region     = "us-east-1"
  access_key = "abcjdfdjvivj"
  secret_key = "jnverjferfvnjgnv"
}

data "aws_vpc" "existing_vpc" {
  tags = {
    Name = "main"
  }
}


data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }

#   filter {
#     name   = "availability-zone"
#     values = ["ca-central-1a", "ca-central-1b"]
#   }
}


# data "aws_ami_ids" "linux" {
#   owners = ["amazon"]
  
#   filter {
#     name   = "name"
#     values = ["al2023-ami-*-kernel-6.1-x86_64"]
#   }
# }
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = data.aws_vpc.existing_vpc.id

  tags = {
    Name = "alb_sg"
  }
}


resource "aws_vpc_security_group_ingress_rule" "alb_rule" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}
resource "aws_vpc_security_group_egress_rule" "alb_rule" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = "0"
  ip_protocol = "tcp"
  to_port     = "65535"
}

resource "aws_security_group" "asg_sg" {
  name        = "asg-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = data.aws_vpc.existing_vpc.id

  tags = {
    Name = "asg_sg"
  }
}


resource "aws_vpc_security_group_ingress_rule" "asg_rule_http" {
  security_group_id = aws_security_group.asg_sg.id
  referenced_security_group_id= aws_security_group.alb_sg.id
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "asg_rule_ssh" {
  security_group_id = aws_security_group.asg_sg.id
 cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}
resource "aws_vpc_security_group_egress_rule" "asg_rule" {
  security_group_id = aws_security_group.asg_sg.id
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = "0"
  ip_protocol = "tcp"
  to_port     = "65535"
}


resource "aws_launch_template" "my-lt" {
  name = "my-lt"
block_device_mappings {
    device_name = "/dev/xvda"
 ebs {
      volume_size = 8
      volume_type = "gp2"
    }
  }
 capacity_reservation_specification {
    capacity_reservation_preference = "open"
  }

image_id = "ami-0f403e3180720dd7e"
instance_initiated_shutdown_behavior = "terminate"
instance_type = "t2.micro"
key_name = "ff"
monitoring {
    enabled = true
  }
network_interfaces {
    associate_public_ip_address = true
    device_index= 0
    security_groups= [aws_security_group.asg_sg.id]

  }
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "test"
    }
  }
user_data = filebase64("${path.module}/userdata.sh")
}


resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for subnet in  data.aws_subnets.selected.ids: subnet]
tags = {
    Environment = "test"
  }
}

resource "aws_lb_target_group" "my_tg" {
  name     = "my-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.existing_vpc.id
  target_type = "instance"
}

resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_tg.arn
  }
}


resource "aws_autoscaling_group" "my_asg" {
  name                      = "my-asg"
  max_size                  = 3
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
 
  vpc_zone_identifier       = [for subnet in  data.aws_subnets.selected.ids: subnet]
   target_group_arns = [aws_lb_target_group.my_tg.arn]

 launch_template {
    id      = aws_launch_template.my-lt.id
    version = aws_launch_template.my-lt.latest_version
  }

}

resource "aws_autoscaling_policy" "my_asg_sp" {
  name                   = "my-asg-sp"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.my_asg.name
  policy_type = "SimpleScaling"
}


resource "aws_cloudwatch_metric_alarm" "my_asg_alarm" {
  alarm_name          = "my-asg-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 20

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.my_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.my_asg_sp.arn]
}

