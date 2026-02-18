# destroy.ps1
# Run this instead of terraform destroy directly
# Scales down ASG to 0 first so instances terminate cleanly
# before Terraform tries to delete VPC/IGW

$ASG_NAME = "hello-world-arm64-ecs-asg"
$REGION = "ap-southeast-2"

Write-Host "Step 1: Scaling down ASG to 0..." -ForegroundColor Yellow
aws autoscaling update-auto-scaling-group --auto-scaling-group-name $ASG_NAME --min-size 0 --max-size 0 --desired-capacity 0 --region $REGION

Write-Host "Step 2: Waiting for EC2 instances to terminate (2 minutes)..." -ForegroundColor Yellow
Start-Sleep -Seconds 120

Write-Host "Step 3: Running terraform destroy..." -ForegroundColor Yellow
terraform destroy -var="log_group_skip_destroy=false"

Write-Host "Done! Remember to manually delete /aws/ecs/containerinsights/hello-world-arm64/performance from CloudWatch." -ForegroundColor Green
