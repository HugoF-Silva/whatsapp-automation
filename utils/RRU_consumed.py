# 40000 read requests unit per sec is the limit

import boto3
import math

def calculate_average_item_size(table_name, region_name='us-east-1'):
    """
    Retrieves the table size and item count from DynamoDB DescribeTable, 
    then calculates the average item size in bytes.
    """
    dynamodb = boto3.client('dynamodb', region_name=region_name)
    response = dynamodb.describe_table(TableName=table_name)
    table = response['Table']
    size_bytes = table['TableSizeBytes']
    item_count = table['ItemCount']

    if item_count == 0:
        raise ValueError("Table has no items, cannot compute average size.")

    avg_size = size_bytes / item_count
    return avg_size


def calculate_rrus(avg_size_bytes):
    """
    Given an average item size in bytes, calculate RRUs for each read consistency.
    """
    # DynamoDB rounds up to the next 4 KB chunk
    chunk_size = 4096.0
    chunks = math.ceil(avg_size_bytes / chunk_size)

    rru_strong = chunks * 1
    rru_eventual = chunks * 0.5
    rru_transactional = chunks * 2

    return {
        'strongly_consistent': rru_strong,
        'eventually_consistent': rru_eventual,
        'transactional': rru_transactional,
        'chunks': chunks
    }


if __name__ == '__main__':
    table_name = 'wait_time_events'
    region = 'us-east-1'  # change to your region

    try:
        avg_size = calculate_average_item_size(table_name, region)
        rrus = calculate_rrus(avg_size)

        print(f"Table: {table_name}")
        print(f"Average item size: {avg_size:.2f} bytes")
        print(f"Rounded-up chunk count: {rrus['chunks']}")
        print("RRUs per read type:")
        print(f"  Strongly consistent: {rrus['strongly_consistent']} RRU(s)")
        print(f"  Eventually consistent: {rrus['eventually_consistent']} RRU(s)") # our cals are eventually consistent
        print(f"  Transactional: {rrus['transactional']} RRU(s)")

    except Exception as e:
        print(f"Error computing RRUs: {e}")
