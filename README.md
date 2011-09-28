= Scalarium =

Scalarium rubygem is a tool for interacting with scalarium and with the ec2 instances.

== Commands ==

    scalarium inspect CLOUDNAME 

See the roles with the instances and their ips.

    scalarium update_sshconfig CLOUDNAME

Update ~/.ssh/config with the hostnames and ips of the cloud.
This enable you to run **ssh machinename** or **scp machinename**.

You can also pass a __-i__ to specify a different pem file or auth key.


    scalarium execute CLOUDNAME ROL_OR_INSTANCE COMMAND

Run a **COMMAND** in **CLOUDNAME** in the rol **ROL_OR_INSTANCE**. If no rol was found, a instances with the name will be used.


    scalarium update_cookbooks CLOUDNAME [ROL_OR_INSTANCE]

Updates the cookbooks in the **CLOUDNAME**. If **ROL_OR_INSTANCE** is present, only the maching roles or instances will be updated.


    scalarium run_recipe CLOUDNAME [ROL_OR_INSTANCE] RECIPE

Run the **RECIPE** in the **CLOUDNAME**. 


    scalarium deploy APPNAME

Deploy **APPNAME**


    scalarium apps

List the available apps.


    scalarium clouds

List the available clodus.

