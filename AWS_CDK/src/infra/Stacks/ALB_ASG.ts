import { CfnOutput, Stack, StackProps,  Fn, Duration } from 'aws-cdk-lib'
import * as ec2 from 'aws-cdk-lib/aws-ec2'
import { Construct } from 'constructs';
import {
    ApplicationLoadBalancer,
    ApplicationTargetGroup,
    ApplicationProtocol,
    TargetType,
    ApplicationListener,
    ListenerAction
} from 'aws-cdk-lib/aws-elasticloadbalancingv2'




import { LaunchTemplate, MachineImage, InstanceType, UserData, } from 'aws-cdk-lib/aws-ec2'
import { AutoScalingGroup, CfnScalingPolicy } from 'aws-cdk-lib/aws-autoscaling'
import { aws_autoscaling as autoscaling } from 'aws-cdk-lib';




export class ALB_ASG extends Stack {
    constructor(scope: Construct, id: string, props?: StackProps) {
        super(scope, id, props);


        const vpcID = 'vpc-0b9b1dfb9fb18d0e9';
        const subnetIds = ['subnet-0b6c27c959fa92b4d', 'subnet-09d2edcc8a75333a6', 'subnet-087b1a0585b791283']


        const vpc = ec2.Vpc.fromVpcAttributes(this, 'Vpc', {
            vpcId: vpcID,
            availabilityZones: ['ca-central-1a', 'ca-central-1b', 'ca-central-1d'], // Specify your AZs
            publicSubnetIds: subnetIds // Specify your subnet IDs
        });
        const userData = UserData.forLinux();
        userData.addCommands(
        '#!/bin/bash',
        '# Use this for your user data (script from top to bottom)',
        '# install httpd (Linux 2 version)',
        'yum update -y',
        'yum install -y httpd',
        'systemctl start httpd',
        'systemctl enable httpd',
        'echo "<h1>Hello World from $(hostname -f)</h1>" > /var/www/html/index.html'
        )

        const alb_sg = new ec2.SecurityGroup(this, 'my-alb-sg', {
            vpc: vpc,
            description: 'Load Balancer Security Group' // Description of the security group
        })

        alb_sg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(80), 'Allow HTTP traffic from anywhere');

        const lb = new ApplicationLoadBalancer(this, 'my-alb', {
            vpc: vpc,
            internetFacing: true,
            securityGroup: alb_sg
        });



        const targetGroup = new ApplicationTargetGroup(this, 'my-tg', {
            targetGroupName: 'my-tg',
            port: 80,
            protocol: ApplicationProtocol.HTTP,
            targetType: TargetType.INSTANCE,
            vpc: vpc,
            
        })
        
       
        const sg = new ec2.SecurityGroup(this, 'my-sg', {
            vpc: vpc,
            description: 'Load Balancer Security Group' // Description of the security group
          })
          sg.addIngressRule(ec2.Peer.securityGroupId(alb_sg.securityGroupId), ec2.Port.tcp(80), 'Allow HTTP traffic from anywhere');
          sg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(22), 'Allow SSH traffic from anywhere');

          const mylaunchTemplate = new LaunchTemplate(this, 'my-launch-template', {
            launchTemplateName: 'my-launch-template',
            machineImage: MachineImage.latestAmazonLinux2(),
            instanceType: new InstanceType('t2.micro'),
            userData: userData,
            keyName: 'my-key',
            blockDevices: [
              {
                deviceName: '/dev/xvda',
                volume: autoscaling.BlockDeviceVolume.ebs(8, {
                  volumeType: autoscaling.EbsDeviceVolumeType.GP2
                }),
              },
            ],
            associatePublicIpAddress: true,
            securityGroup: sg
          
          
          })
          
         
          
          const asg = new AutoScalingGroup(this, 'my-asg', {
            autoScalingGroupName: 'my-asg',
            vpc: vpc,
            launchTemplate: mylaunchTemplate,
            minCapacity: 2,
            maxCapacity: 3,
            desiredCapacity: 2,
            vpcSubnets: {
              subnetType: ec2.SubnetType.PUBLIC,
            },
           
          
          })
          asg.scaleOnCpuUtilization('my-scaling-policy', {targetUtilizationPercent: 20,
            disableScaleIn: false,
            cooldown:  Duration.minutes(5)})

        
        targetGroup.addTarget(asg)

        const listener = new ApplicationListener(this, 'My-Listener', {
            port: 80,
            protocol: ApplicationProtocol.HTTP,
            loadBalancer: lb,
            defaultAction: ListenerAction.forward([targetGroup])
        })

        new CfnOutput(this, 'LoadBalancerDNS', { exportName: 'LoadBalancerDNS', value: lb.loadBalancerDnsName });
        new CfnOutput(this, 'LoadBalancerSG', { exportName: 'LoadBalancerSG', value: alb_sg.securityGroupId });
    }
}