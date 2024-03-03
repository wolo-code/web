# Wolo Code - web

## Technology:
- Nginx - aggregator reverse proxy, docker based
- Supports HTTPS with a self-signed certificate
- Routes to components Wolo-code : [`web-app`](https://github.com/wolo-code/web-app) & [`web-site`](https://github.com/wolo-code/web-site) - both docker based

## Localhost - hosts file

- local.wolo.codes - 127.0.0.1

## Project stcuture

```
Web
│
├── App
│   └── Project             (wolo-code/web-app)
│       ├── interim
│       └── public
│
├── Site
│   └── Project             (wolo-code/web-site)
|       ├── root\framework  (blank-org/cutie - submoduled)
│       ├── interim
│       └── public
│
├── Project                 (wolo-code/web * this repo)
│   ├── interim             (wolo-code/web-interim)
│   └── public              (wolo-code/web-public > wolo.codes)
|
│
└── Tiggu                   (blank-org/tiggu)
│
└── Firebase                (blank-org/firebase)
```

## Certificate

For SSL generate `server.key` & `server.crt` files

cert_details.txt :

```
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = local.wolo.codes
```

Generate self-signed certificate
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout server.key -out server.crt -config cert_details.txt
```

You may also want to add this to your trusted-root CA store  
\- so that you are not presented with the *insecure origin* message when navigating to `local.wolo.codes`


## Manage
`Firebase` : docker based - project is to provide firebase CLI.  
Used to setup CI; Not required afterwards - hence separate.

## Website
`wolo.codes` \> mapped to `public` directory

## Setup
- Run following script to setup the directory structure & repos
```bash
base_directory="web"

# function to create directory and clone git repository
clone_repo() {
    local path=$1
    local remote_url=$2
    local full_path="$base_directory/$path"

    # create base directory if it doesn't exist
    mkdir -p "$base_directory"
    
    # clone the repository into the specified path
    git clone --recurse-submodules "$remote_url" "$full_path"
}

# clone git repositories into specific paths
clone_repo "app/project" "https://github.com/wolo-code/web-app.git"
clone_repo "site/project" "https://github.com/wolo-code/web-site.git"
clone_repo "project" "https://github.com/wolo-code/web.git"
clone_repo "project/interim" "https://github.com/wolo-code/web-interim.git"
clone_repo "project/public" "https://github.com/wolo-code/web-public.git"
clone_repo "tiggu" "https://github.com/blank-org/tiggu.git"
# clone_repo "firebase" "https://github.com/blank-org/firebase.git"
```

- Then build and run docker for `web\project`
