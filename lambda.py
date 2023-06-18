import boto3
import pandas as pd
from io import BytesIO

def lambda_handler(event, context):
    # Retrieve the S3 bucket and file details from the lambda event
    s3_bucket = event['Records'][0]['s3']['bucket']['name']
    s3_key = event['Records'][0]['s3']['object']['key']

    # Create a Boto3 S3 client
    s3_client = boto3.client('s3')

    # Download the CSV file from S3
    response = s3_client.get_object(Bucket=s3_bucket, Key=s3_key)
    csv_content = response['Body'].read().decode('utf-8')

    # Convert the CSV data to RDF using pandas
    df = pd.read_csv(BytesIO(csv_content))
    rdf_data = df.to_rdf()

    # Define the output file name with .rdf extension
    rdf_key = s3_key.replace('.csv', '.rdf')

    # Upload the RDF data to S3
    s3_client.put_object(Body=rdf_data, Bucket=s3_bucket, Key=rdf_key)

    return {
        'statusCode': 200,
        'body': 'CSV to RDF conversion completed.'
    }