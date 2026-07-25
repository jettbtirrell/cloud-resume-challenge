import json
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("visitor-count")

def lambda_handler(event, context):
    response = table.update_item(
        Key={"id": "visitor-count"},
        UpdateExpression="SET #c = if_not_exists(#c, :start) + :incr",
        ExpressionAttributeNames={"#c": "count"},
        ExpressionAttributeValues={":start": 0, ":incr": 1},
        ReturnValues="UPDATED_NEW"
    )

    new_count = response["Attributes"]["count"]

    return {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps({"count": int(new_count)})
    }