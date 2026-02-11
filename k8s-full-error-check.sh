#!/bin/bash
#################################
# CHANGE ONLY THIS
#################################
NAMESPACE=chat-app
#################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=============================================="
echo " K8s FULL ERROR DIAGNOSTIC (READ-ONLY)"
echo " Namespace: $NAMESPACE"
echo "=============================================="
echo

# Namespace check
kubectl get ns $NAMESPACE &>/dev/null || {
  echo -e "${RED}❌ Namespace not found${NC}"
  exit 1
}

#################################
# 1️⃣ YAML / MANIFEST LEVEL ERRORS
#################################
echo -e "${YELLOW}1️⃣ YAML / Manifest related issues (runtime signals)${NC}"
kubectl get deploy -n $NAMESPACE &>/dev/null || echo "⚠️ Deployment parsing issue"
echo

#################################
# 2️⃣ IMAGE & REGISTRY ERRORS
#################################
echo -e "${YELLOW}2️⃣ Image / Registry errors${NC}"
kubectl get pods -n $NAMESPACE | grep -E "ImagePullBackOff|ErrImagePull" && \
echo -e "${RED}❌ Image pull issue detected${NC}" || \
echo -e "${GREEN}✅ No image pull issue${NC}"
echo

#################################
# 3️⃣ POD LIFECYCLE ERRORS
#################################
echo -e "${YELLOW}3️⃣ Pod lifecycle issues${NC}"
kubectl get pods -n $NAMESPACE | grep -E "CrashLoopBackOff|RunContainerError|CreateContainerConfigError|OOMKilled|Completed" || \
echo -e "${GREEN}✅ No pod lifecycle errors${NC}"
echo

#################################
# 4️⃣ APPLICATION / RUNTIME ERRORS
#################################
echo -e "${YELLOW}4️⃣ Application runtime errors (log scan)${NC}"
for pod in $(kubectl get pods -n $NAMESPACE --no-headers | awk '{print $1}')
do
  kubectl logs $pod -n $NAMESPACE --tail=20 2>/dev/null | \
  grep -E "EADDRINUSE|Connection refused|Permission denied|Cannot find module|File not found|ENV" && \
  echo -e "${RED}❌ Runtime error in pod: $pod${NC}"
done
echo

#################################
# 5️⃣ CONFIGMAP & SECRET ERRORS
#################################
echo -e "${YELLOW}5️⃣ ConfigMap / Secret issues${NC}"
kubectl describe pod -n $NAMESPACE $(kubectl get pods -n $NAMESPACE --no-headers | awk '{print $1}') | \
grep -E "configmap not found|secret not found|MountVolume.SetUp failed|base64" && \
echo -e "${RED}❌ Config / Secret issue detected${NC}"
echo

#################################
# 6️⃣ RESOURCE & SCHEDULING ERRORS
#################################
echo -e "${YELLOW}6️⃣ Resource & Scheduling issues${NC}"
kubectl describe pod -n $NAMESPACE | \
grep -E "Insufficient cpu|Insufficient memory|FailedScheduling|NodeNotReady" && \
echo -e "${RED}❌ Scheduling issue detected${NC}"
echo

#################################
# 7️⃣ SERVICE & NETWORKING ERRORS
#################################
echo -e "${YELLOW}7️⃣ Service & networking issues${NC}"
kubectl get svc -n $NAMESPACE
kubectl describe svc -n $NAMESPACE | grep -E "Endpoints not found|targetPort" && \
echo -e "${RED}❌ Service selector / port issue${NC}"
echo

#################################
# 8️⃣ INGRESS ERRORS
#################################
echo -e "${YELLOW}8️⃣ Ingress issues${NC}"
kubectl get ingress -n $NAMESPACE &>/dev/null && \
kubectl describe ingress -n $NAMESPACE | grep -E "404|502|503|default backend|tls secret not found" || \
echo "ℹ️ No ingress or no ingress errors"
echo

#################################
# 9️⃣ DNS ERRORS
#################################
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50 2>/dev/null | \
grep -E "SERVFAIL|no such host" && \
echo -e "${RED}❌ Critical DNS issue detected${NC}"

#################################
# READINESS / LIVENESS PROBE FAILURES
#################################
echo -e "${YELLOW}❤️ Health probe issues${NC}"
kubectl describe pod -n $NAMESPACE | \
grep -E "Readiness probe failed|Liveness probe failed" && \
echo -e "${RED}❌ Probe failure detected${NC}"
echo

#################################
# PENDING / TERMINATING PODS
#################################
echo -e "${YELLOW}⏳ Pending / Terminating pods${NC}"
kubectl get pods -n $NAMESPACE | \
grep -E "Pending|Terminating" && \
echo -e "${RED}❌ Pod stuck state detected${NC}"
echo

#################################
# HPA ISSUES
#################################
echo -e "${YELLOW}📈 HPA issues${NC}"
kubectl get hpa -n $NAMESPACE &>/dev/null && \
kubectl describe hpa -n $NAMESPACE | \
grep -E "FailedGetResourceMetric|ScalingLimited" && \
echo -e "${RED}❌ HPA issue detected${NC}" || \
echo "ℹ️ HPA not configured"
echo

#################################
# RESOURCE LIMITS CHECK
#################################
echo -e "${YELLOW}📦 Resource limits check${NC}"
kubectl get pod -n $NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources}{"\n"}{end}' | \
grep -E "\{\}" && \
echo -e "${RED}❌ Resource limits/requests missing${NC}"
echo

#################################
# SERVICE → POD SELECTOR MATCH
#################################
echo -e "${YELLOW}🎯 Service selector validation${NC}"
for svc in $(kubectl get svc -n $NAMESPACE --no-headers | awk '{print $1}')
do
  endpoints=$(kubectl get endpoints $svc -n $NAMESPACE -o jsonpath='{.subsets}')
  [[ -z "$endpoints" ]] && echo -e "${RED}❌ Service $svc has no endpoints${NC}"
done
echo

#################################
# HIGH RESTART COUNT
#################################
kubectl get pods -n $NAMESPACE --no-headers | awk '$4 > 3 {print}' && \
echo -e "${RED}❌ High restart count detected${NC}"

#################################
# 🔟 NODE LEVEL ERRORS
#################################

kubectl get nodes --no-headers | awk '$2 != "Ready" {print}' && \
echo -e "${RED}❌ Node not ready detected${NC}"



#################################
# 1️⃣1️⃣ STORAGE / VOLUME ERRORS
#################################
echo -e "${YELLOW}1️⃣1️⃣ Storage / Volume issues${NC}"
kubectl get pvc -n $NAMESPACE &>/dev/null && \
kubectl describe pvc -n $NAMESPACE | grep -E "Pending|VolumeMount failed|Read-only file system|permission denied"
echo

#################################
# 1️⃣2️⃣ RBAC / PERMISSION ERRORS
#################################
echo -e "${YELLOW}1️⃣2️⃣ RBAC / Permission issues${NC}"
kubectl auth can-i get pods -n $NAMESPACE || \
echo -e "${RED}❌ RBAC permission issue${NC}"
echo

#################################
# 1️⃣3️⃣ HELM RELATED ERRORS
#################################
echo -e "${YELLOW}1️⃣3️⃣ Helm related issues${NC}"
helm list -n $NAMESPACE &>/dev/null && \
helm list -n $NAMESPACE || echo "ℹ️ Helm not used in this namespace"
echo


#################################
# 1️⃣4️⃣ NAMESPACE STORAGE (PVC BASED)
#################################
echo -e "${YELLOW}🗄️ Namespace storage usage (PVCs)${NC}"

kubectl get pvc -n $NAMESPACE &>/dev/null || {
  echo "ℹ️ No PVC found in namespace"
  exit 0
}

echo
echo "➡️ PVC size requested:"
kubectl get pvc -n $NAMESPACE \
-o custom-columns=PVC:.metadata.name,STATUS:.status.phase,SIZE:.spec.resources.requests.storage,STORAGECLASS:.spec.storageClassName

echo
echo "➡️ Total PVC storage (requested):"
kubectl get pvc -n $NAMESPACE \
-o jsonpath='{range .items[*]}{.spec.resources.requests.storage}{"\n"}{end}' | \
awk '
/Gi/ {gsub("Gi",""); sum+=$1}
/Mi/ {gsub("Mi",""); sum+=($1/1024)}
END {printf "TOTAL ≈ %.2f Gi\n", sum}
'
echo


echo "=============================================="
echo -e "${GREEN}✅ FULL DIAGNOSTIC COMPLETED (NO CHANGES MADE)${NC}"
echo "=============================================="
