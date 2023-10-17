import requests
import os

headers = {"Content-Type": "application/json"}

url = f"https://zenodo.org/api/deposit/depositions?access_token=${os.environ["ACCESS_TOKEN"]}"

filename = "*.vcf.gz"
path = "./variant_calling/%s" % filename

with open(path, "rb") as fp:
    r = requests.post(
        "%s/%s" % (bucket_url, filename),
        data=fp,
        params=params,
    )
r.json()

data = {
    'metadata': {
        'title': 'My first upload',
        'upload_type': 'poster',
        'description': 'This is my first upload',
        'creators': [{'name': 'Doe, John',
                    'affiliation': 'Zenodo'}]
    }
}

r = requests.post(url, data=json.dumps(data), headers=headers)
r.status_code
# 200