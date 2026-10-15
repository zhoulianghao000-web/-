"""Validate V2.3 contract with credential-redacted real HTTP samples."""
import argparse,json,re
from pathlib import Path
from urllib.parse import urlsplit
import yaml
from openapi_spec_validator import validate_spec
from jsonschema import Draft202012Validator,FormatChecker
from referencing import Registry,Resource
from referencing.jsonschema import DRAFT202012
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--samples',type=Path,required={(path,m,'200') for path,m,op in ops if 'business-analytics' in path}
assert required<=covered,required-covered
assert {('/merchant/business-analytics','get',s) for s in ['400','401','403','404','422']}<=covered
report={'result':'PASS','operations':len(ops),'actual_analytics_responses':count,'covered_responses':[list(x) for x in sorted(covered)]};a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8');print(json.dumps(report))
