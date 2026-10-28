# Vommet web on Kubernetes

A kustomize base for the Vommet web app image,
`ghcr.io/dark-collective/vommet-web`: nginx serving the static app on port
8080, unprivileged (uid 101). It is a plain web page; the browser talks to the
homeserver directly, so there is no state, database or secret to deploy.

| File | What |
|---|---|
| `deployment.yaml` | one replica, readiness/liveness on `/`, non-root |
| `service.yaml` | ClusterIP service `vommet-web`, port 80 → 8080 |
| `ingress.yaml` | optional; not applied until you set a host and enable it |
| `kustomization.yaml` | the above, plus the image tag |

## Deploy

```sh
kubectl create namespace vommet
kubectl apply -n vommet -k contrib/k8s
kubectl -n vommet port-forward svc/vommet-web 8080:80
```

Then open http://localhost:8080. For real use, serve it over HTTPS (the app
needs a secure context): set the host in `ingress.yaml` and uncomment it in
`kustomization.yaml`, or point your own Ingress/Gateway at service
`vommet-web`, port `web`.

## Image tags

- `testing`: moves to each testing release (the default here).
- `testing-YYYY-MM-DD[letter]`: one release; pin one of these to choose when
  you upgrade (`images[0].newTag` in `kustomization.yaml`).
- `latest` and stable release tags appear once stable releases are published.

## Configuration

Environment variables, read when the container starts (unset = the image's
defaults):

| Variable | Default | What |
|---|---|---|
| `VOMMET_DEFAULT_HOMESERVER` | built into the image | homeserver pre-filled on the login page (a server name such as `example.org`) |
| `VOMMET_CROSS_ORIGIN_ISOLATION` | `on` | `off` drops the COOP/COEP headers (the renderer then runs single-threaded); only for setups embedding cross-origin pages that don't send COEP/CORP |
| `TZ` | `UTC` | timezone of the nginx logs |

Override them, and anything else, from your own overlay instead of editing
the base:

```yaml
# my-vommet/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: vommet
resources:
  - ../contrib/k8s
images:
  - name: ghcr.io/dark-collective/vommet-web
    newTag: testing-2026-10-26d
patches:
  - target:
      kind: Deployment
      name: vommet-web
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env
        value:
          - name: VOMMET_DEFAULT_HOMESERVER
            value: example.org
          - name: TZ
            value: Europe/Berlin
```
