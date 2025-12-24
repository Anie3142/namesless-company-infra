#!/usr/bin/env python3
"""
Extract AWS SSO credentials and export as environment variables for Terraform
"""
import json
import subprocess
import sys
from pathlib import Path

def get_sso_credentials():
    """Get AWS SSO credentials from the AWS CLI"""
    try:
        # Run aws sts get-caller-identity to ensure we're authenticated
        result = subprocess.run(
            ['aws', 'sts', 'get-caller-identity', '--profile', 'default'],
            capture_output=True,
            text=True,
            env={'AWS_SDK_LOAD_CONFIG': '1'}
        )
        
        if result.returncode != 0:
            print("Error: Not authenticated with AWS SSO", file=sys.stderr)
            print("Please run: aws sso login --profile=default", file=sys.stderr)
            sys.exit(1)
        
        # Get credentials from AWS CLI cache
        cache_dir = Path.home() / '.aws' / 'cli' / 'cache'
        
        # Try to get credentials using boto3 if available
        try:
            import boto3
            session = boto3.Session(profile_name='default')
            credentials = session.get_credentials()
            
            if credentials:
                print(f"export AWS_ACCESS_KEY_ID='{credentials.access_key}'")
                print(f"export AWS_SECRET_ACCESS_KEY='{credentials.secret_key}'")
                if credentials.token:
                    print(f"export AWS_SESSION_TOKEN='{credentials.token}'")
                print(f"export AWS_DEFAULT_REGION='us-east-1'")
                return
        except ImportError:
            pass
        
        # Fallback: Just use the profile
        print("export AWS_PROFILE='default'")
        print("export AWS_SDK_LOAD_CONFIG='1'")
        print("export AWS_DEFAULT_REGION='us-east-1'")
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    get_sso_credentials()
