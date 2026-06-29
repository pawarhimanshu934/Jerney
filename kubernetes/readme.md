Command to connect your kubectl with AWS EKS Cluster :
-> aws eks update-kubeconfig --region <region-code> --name <cluster-name>
-> aws eks update-kubeconfig --region us-east-1 --name Jerney

* For "gp3" storage class, you need to create StorageClass manifest. Unlike "gp2", it doesn't come by default.

* Network Policies are introduced to secure backend and database pods from attackers,
  1) Databse POD should only recieve traffic from Backend POD and block others.
  2) Backend POD should only recieve traffic from Frontend POD and block others.

* When working with databases, always use StatefulSets with headless service( CluserIP : None )



