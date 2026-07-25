import unittest
from moto import mock_aws
import boto3
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import lambda_function


class TestVisitorCounter(unittest.TestCase):

    @mock_aws
    def setUp(self):
        self.dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        self.table = self.dynamodb.create_table(
            TableName="visitor-count",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST"
        )
        lambda_function.table = self.table

    @mock_aws
    def test_first_invocation_creates_and_increments(self):
        self.setUp()
        response = lambda_function.lambda_handler({}, {})
        self.assertEqual(response["statusCode"], 200)
        body = response["body"]
        self.assertIn('"count": 1', body)

    @mock_aws
    def test_second_invocation_increments_again(self):
        self.setUp()
        lambda_function.lambda_handler({}, {})
        response = lambda_function.lambda_handler({}, {})
        self.assertIn('"count": 2', response["body"])

    @mock_aws
    def test_response_has_cors_header(self):
        self.setUp()
        response = lambda_function.lambda_handler({}, {})
        self.assertEqual(response["headers"]["Access-Control-Allow-Origin"], "*")


if __name__ == "__main__":
    unittest.main()