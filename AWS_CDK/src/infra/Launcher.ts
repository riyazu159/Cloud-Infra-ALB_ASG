import {App} from 'aws-cdk-lib'
import { ALB_ASG } from './Stacks/ALB_ASG';
 

const app= new App();

new ALB_ASG(app, 'ALB-ASG', {env: {
    account: '184809832981',
    region: 'ca-central-1'
  }});