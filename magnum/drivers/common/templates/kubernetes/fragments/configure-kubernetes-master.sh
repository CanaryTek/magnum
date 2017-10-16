#!/bin/sh

. /etc/sysconfig/heat-params

echo "configuring kubernetes (master)"

sed -i '
  /^ETCD_LISTEN_CLIENT_URLS=/ s/=.*/="http:\/\/0.0.0.0:2379"/
' /etc/etcd/etcd.conf

sed -i '
  /^KUBE_ALLOW_PRIV=/ s/=.*/="--allow_privileged='"$KUBE_ALLOW_PRIV"'"/
' /etc/kubernetes/config

KUBE_API_ARGS="--runtime_config=api/all=true"
if [ "$TLS_DISABLED" == "True" ]; then
    KUBE_API_ADDRESS="--insecure-bind-address=0.0.0.0 --insecure-port=$KUBE_API_PORT"
else
    KUBE_API_ADDRESS="--bind_address=0.0.0.0 --secure-port=$KUBE_API_PORT"
    # insecure port is used internaly
    KUBE_API_ADDRESS="$KUBE_API_ADDRESS --insecure-port=8080"
    KUBE_API_ARGS="$KUBE_API_ARGS --tls_cert_file=/srv/kubernetes/server.crt"
    KUBE_API_ARGS="$KUBE_API_ARGS --tls_private_key_file=/srv/kubernetes/server.key"
    KUBE_API_ARGS="$KUBE_API_ARGS --client_ca_file=/srv/kubernetes/ca.crt"
    KUBE_API_ARGS="$KUBE_API_ARGS --kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP"
fi

KUBE_ADMISSION_CONTROL=""
if [ -n "${ADMISSION_CONTROL_LIST}" ] && [ "${TLS_DISABLED}" == "False" ]; then
    KUBE_ADMISSION_CONTROL="--admission-control=${ADMISSION_CONTROL_LIST}"
fi

if [ -n "$TRUST_ID" ]; then
    KUBE_API_ARGS="$KUBE_API_ARGS --cloud-config=/etc/sysconfig/kube_openstack_config --cloud-provider=openstack"
fi

sed -i '
  /^KUBE_API_ADDRESS=/ s/=.*/='"${KUBE_API_ADDRESS}"'/
  /^KUBE_SERVICE_ADDRESSES=/ s|=.*|="--service-cluster-ip-range='"$PORTAL_NETWORK_CIDR"'"|
  /^KUBE_API_ARGS=/ s/KUBE_API_ARGS.//
  /^KUBE_ETCD_SERVERS=/ s/=.*/="--etcd_servers=http:\/\/127.0.0.1:2379"/
  /^KUBE_ADMISSION_CONTROL=/ s/=.*/="'"${KUBE_ADMISSION_CONTROL}"'"/
' /etc/kubernetes/apiserver
cat << _EOC_ >> /etc/kubernetes/apiserver
KUBE_API_ARGS="$KUBE_API_ARGS"
_EOC_

# Add controller manager args
KUBE_CONTROLLER_MANAGER_ARGS=""
if [ -n "${ADMISSION_CONTROL_LIST}" ] && [ "${TLS_DISABLED}" == "False" ]; then
    KUBE_CONTROLLER_MANAGER_ARGS="--service-account-private-key-file=/srv/kubernetes/server.key"
fi

if [ -n "$TRUST_ID" ]; then
    KUBE_CONTROLLER_MANAGER_ARGS="$KUBE_CONTROLLER_MANAGER_ARGS --cloud-config=/etc/sysconfig/kube_openstack_config --cloud-provider=openstack"
fi

sed -i '
  /^KUBELET_ADDRESSES=/ s/=.*/="--machines='""'"/
  /^KUBE_CONTROLLER_MANAGER_ARGS=/ s#\(KUBE_CONTROLLER_MANAGER_ARGS\).*#\1="'"${KUBE_CONTROLLER_MANAGER_ARGS}"'"#
' /etc/kubernetes/controller-manager

HOSTNAME_OVERRIDE=$(hostname --short | sed 's/\.novalocal//')
KUBELET_ARGS="--register-node=true --register-schedulable=false --config=/etc/kubernetes/manifests --hostname-override=${HOSTNAME_OVERRIDE}"
KUBELET_ARGS="${KUBELET_ARGS} --cluster_dns=${DNS_SERVICE_IP} --cluster_domain=${DNS_CLUSTER_DOMAIN}"

if [ -n "${INSECURE_REGISTRY_URL}" ]; then
    KUBELET_ARGS="${KUBELET_ARGS} --pod-infra-container-image=${INSECURE_REGISTRY_URL}/google_containers/pause\:0.8.0"
    echo "INSECURE_REGISTRY='--insecure-registry ${INSECURE_REGISTRY_URL}'" >> /etc/sysconfig/docker
fi

sed -i '
  /^KUBELET_ADDRESS=/ s/=.*/="--address=0.0.0.0"/
  /^KUBELET_HOSTNAME=/ s/=.*/=""/
  /^KUBELET_ARGS=/ s|=.*|='"$KUBELET_ARGS"'|
' /etc/kubernetes/kubelet
