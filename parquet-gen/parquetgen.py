#!/usr/bin/env python3
# generate_parquet.py
# Usage: python generate_parquet.py 500 output.parquet
# Generates ~500 MB parquet file.

import argparse
import os
import random
import string
import uuid
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq
from faker import Faker


fake = Faker()


def random_string(n: int) -> str:
    return "".join(random.choices(string.ascii_letters + string.digits, k=n))


def make_batch(rows: int) -> pa.Table:
    return pa.table({
        "id": [str(uuid.uuid4()) for _ in range(rows)],
        "name": [fake.name() for _ in range(rows)],
        "email": [fake.email() for _ in range(rows)],
        "address": [fake.address().replace("\n", ", ") for _ in range(rows)],
        "city": [fake.city() for _ in range(rows)],
        "state": [fake.state() for _ in range(rows)],
        "country": [fake.country() for _ in range(rows)],
        "latitude": [float(fake.latitude()) for _ in range(rows)],
        "longitude": [float(fake.longitude()) for _ in range(rows)],
        "phone": [fake.phone_number() for _ in range(rows)],
        "company": [fake.company() for _ in range(rows)],
        "payload": [random_string(256) for _ in range(rows)],  # helps grow file size
    })


def generate_parquet(target_mb: int, output_file: str, batch_rows: int = 10_000):
    target_bytes = target_mb * 1024 * 1024
    output_path = Path(output_file)

    if output_path.exists():
        output_path.unlink()

    writer = None
    total_rows = 0

    try:
        while True:
            table = make_batch(batch_rows)

            if writer is None:
                writer = pq.ParquetWriter(
                    output_path,
                    table.schema,
                    compression="snappy",
                )

            writer.write_table(table)
            total_rows += batch_rows

            if output_path.exists() and output_path.stat().st_size >= target_bytes:
                break

            size_mb = output_path.stat().st_size / (1024 * 1024)
            print(f"rows={total_rows:,}, size={size_mb:.2f} MB", end="\r")

    finally:
        if writer is not None:
            writer.close()

    final_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"\nDone: {output_path}")
    print(f"Rows: {total_rows:,}")
    print(f"Size: {final_mb:.2f} MB")


def main():
    parser = argparse.ArgumentParser(
        description="Generate a parquet file with fake PII-like data."
    )
    parser.add_argument(
        "n",
        type=int,
        help="Target parquet size in MB",
    )
    parser.add_argument(
        "output",
        nargs="?",
        default="fake_data.parquet",
        help="Output parquet file path. Default: fake_data.parquet",
    )
    parser.add_argument(
        "--batch-rows",
        type=int,
        default=10_000,
        help="Rows per write batch. Default: 10000",
    )

    args = parser.parse_args()
    generate_parquet(args.n, args.output, args.batch_rows)


if __name__ == "__main__":
    main()
