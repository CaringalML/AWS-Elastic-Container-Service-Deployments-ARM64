import os
import boto3
import json

def lambda_handler(event, context):
    ecs = boto3.client('ecs')
    cluster = os.environ['CLUSTER']
    service = os.environ['SERVICE']
    task_family = os.environ['TASK_FAMILY']
    container_name = os.environ['CONTAINER_NAME']
    region = os.environ['ECS_REGION']

    # Get the latest task definition
    response = ecs.describe_services(cluster=cluster, services=[service])
    task_def_arn = response['services'][0]['taskDefinition']
    task_def = ecs.describe_task_definition(taskDefinition=task_def_arn)['taskDefinition']

    # Get the new image URI from the ECR event
    detail = event.get('detail', {})
    image_tag = detail.get('image-tag', 'latest')
    repository_name = detail.get('repository-name')
    account_id = event.get('account')
    image_uri = f"{account_id}.dkr.ecr.{region}.amazonaws.com/{repository_name}:{image_tag}"

    # Update container image in the task definition
    new_container_defs = task_def['containerDefinitions']
    for container in new_container_defs:
        if container['name'] == container_name:
            container['image'] = image_uri

    # Register new task definition
    register_kwargs = {
        'family': task_def['family'],
        'taskRoleArn': task_def.get('taskRoleArn'),
        'executionRoleArn': task_def.get('executionRoleArn'),
        'networkMode': task_def['networkMode'],
        'containerDefinitions': new_container_defs,
        'requiresCompatibilities': task_def.get('requiresCompatibilities'),
        'cpu': task_def.get('cpu'),
        'memory': task_def.get('memory'),
        'runtimePlatform': task_def.get('runtimePlatform'),
    }
    # Remove None values
    register_kwargs = {k: v for k, v in register_kwargs.items() if v is not None}
    new_task_def = ecs.register_task_definition(**register_kwargs)
    new_task_def_arn = new_task_def['taskDefinition']['taskDefinitionArn']

    # Update ECS service to use new task definition
    ecs.update_service(
        cluster=cluster,
        service=service,
        taskDefinition=new_task_def_arn
    )

    return {
        'statusCode': 200,
        'body': json.dumps('ECS service updated to new image: ' + image_uri)
    }
