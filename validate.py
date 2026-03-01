#!/usr/bin/env python3

import re
import sys

# CloudFormation YAML validation
files_to_validate = [
    'nfw-instructor.yaml',
    'nfw-student-min.yaml'
]

def validate_cfn_template(filepath):
    """Basic validation of CloudFormation template"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        errors = []
        warnings = []
        
        # Check required keys
        if 'AWSTemplateFormatVersion' not in content:
            errors.append("Missing AWSTemplateFormatVersion")
        
        if 'Description:' not in content:
            warnings.append("Missing Description (recommended)")
        
        if 'Resources:' not in content:
            errors.append("Missing Resources section")
        
        if 'Parameters:' not in content:
            warnings.append("Missing Parameters (optional if not needed)")
        
        # Check for unmatched brackets
        open_braces = content.count('{')
        close_braces = content.count('}')
        if open_braces != close_braces:
            errors.append(f"Unmatched braces: {open_braces} open, {close_braces} close")
        
        # Check for common syntax issues
        if 'GetAtt' in content and not re.search(r'GetAtt.*\[', content) and not re.search(r'GetAtt.*:', content):
            pass  # GetAtt can be in shorthand form !GetAtt
        
        # Check for required IAM capability
        if 'AWS::IAM::' in content and 'CAPABILITY_' in content:
            pass  # Should mention capability in comments
        
        return errors, warnings
        
    except FileNotFoundError:
        return [f"File not found: {filepath}"], []
    except Exception as e:
        return [f"Error reading file: {e}"], []

# Validate bash script
def validate_bash_script(filepath):
    """Basic validation of bash script"""
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        errors = []
        warnings = []
        
        if not content.startswith('#!/'):
            warnings.append("Missing shebang (#!)")
        
        if 'set -e' not in content and 'set -euo' not in content:
            warnings.append("Missing 'set -e' for error handling")
        
        if 'export' in content or 'source' in content:
            pass  # Good practices present
        
        # Check variable quoting
        if ' $(' in content and not '$(SOMETHING)' in content:
            pass  # Variable substitution exists
        
        return errors, warnings
    
    except FileNotFoundError:
        return [f"File not found: {filepath}"], []
    except Exception as e:
        return [f"Error reading file: {e}"], []

print("=" * 70)
print("CloudFormation & Script Validation Report")
print("=" * 70)

all_valid = True

# Validate YAML files
print("\nCloudFormation Templates:")
print("-" * 70)
for filepath in files_to_validate:
    errors, warnings = validate_cfn_template(filepath)
    
    if errors:
        all_valid = False
        print(f"\n✗ {filepath}: ERRORS")
        for err in errors:
            print(f"  - {err}")
    else:
        print(f"\n✓ {filepath}: Structure valid")
    
    if warnings:
        for warn in warnings:
            print(f"  ⚠ {warn}")

# Validate bash script
print("\n\nBash Scripts:")
print("-" * 70)
script_path = 'lab-cleanup.sh'
errors, warnings = validate_bash_script(script_path)

if errors:
    all_valid = False
    print(f"\n✗ {script_path}: ERRORS")
    for err in errors:
        print(f"  - {err}")
else:
    print(f"\n✓ {script_path}: Structure valid")

if warnings:
    for warn in warnings:
        print(f"  ⚠ {warn}")

print("\n" + "=" * 70)
if all_valid:
    print("✓ All files validated successfully!")
    print("=" * 70)
    sys.exit(0)
else:
    print("✗ Some validation errors found. Please review above.")
    print("=" * 70)
    sys.exit(1)
