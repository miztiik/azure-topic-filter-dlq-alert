// targetScope = 'subscription'

targetScope = 'resourceGroup'

// Parameters
param deploymentParams object
param identity_params object
param key_vault_params object

param storageAccountParams object

param logAnalyticsWorkspaceParams object
param dceParams object
param brand_tags object

param vnet_params object
param funcParams object
param svc_bus_params object

param cosmosDbParams object

param dateNow string = utcNow('yyyy-MM-dd-hh-mm')

param tags object = union(brand_tags, { last_deployed: dateNow })

@description('Create Identity')
module r_uami 'modules/identity/create_uami.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_uami'
  params: {
    deploymentParams: deploymentParams
    identity_params: identity_params
    tags: tags
  }
}

@description('Add Permissions to User Assigned Managed Identity(UAMI)')
module r_add_perms_to_uami 'modules/identity/assign_perms_to_uami.bicep' = {
  name: 'perms_provider_to_uami_${deploymentParams.global_uniqueness}'
  params: {
    uami_name_akane: r_uami.outputs.uami_name_akane
  }
  dependsOn: [
    r_uami
  ]
}

@description('Create Key Vault')
module r_kv 'modules/security/create_key_vault.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_kv'
  params: {
    deploymentParams: deploymentParams
    key_vault_params: key_vault_params
    tags: tags
    uami_name_akane: r_uami.outputs.uami_name_akane
  }
}

@description('Create Cosmos DB')
module r_cosmosdb 'modules/database/cosmos.bicep' = {
  name: '${cosmosDbParams.cosmosDbNamePrefix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_cosmos_db'
  params: {
    deploymentParams: deploymentParams
    cosmosDbParams: cosmosDbParams
    tags: tags
  }
}

@description('Create the Log Analytics Workspace')
module r_logAnalyticsWorkspace 'modules/monitor/log_analytics_workspace.bicep' = {
  name: '${logAnalyticsWorkspaceParams.name_prefix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_la'
  params: {
    deploymentParams: deploymentParams
    logAnalyticsWorkspaceParams: logAnalyticsWorkspaceParams
    tags: tags
  }
}

@description('Create Storage Account')
module r_sa 'modules/storage/create_storage_account.bicep' = {
  name: '${storageAccountParams.storageAccountNamePrefix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_sa'
  params: {
    deploymentParams: deploymentParams
    storageAccountParams: storageAccountParams
    funcParams: funcParams
    tags: tags
    logAnalyticsWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId
    enableDiagnostics: true
  }
}

@description('Create Storage Account - Blob container')
module r_blob 'modules/storage/create_blob.bicep' = {
  name: '${storageAccountParams.storageAccountNamePrefix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_blob'
  params: {
    deploymentParams: deploymentParams
    storageAccountParams: storageAccountParams
    storageAccountName: r_sa.outputs.saName
    storageAccountName_1: r_sa.outputs.saName_1
  }
  dependsOn: [
    r_sa
    r_logAnalyticsWorkspace
  ]
}

@description('Create the function app & Functions')
module r_fn_app 'modules/functions/create_function.bicep' = {
  name: '${funcParams.funcNamePrefix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_fn_app'
  params: {
    deploymentParams: deploymentParams
    uami_name_func: r_uami.outputs.uami_name_func
    funcParams: funcParams
    funcSaName: r_sa.outputs.saName_1

    logAnalyticsWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId
    enableDiagnostics: true
    tags: tags

    // appConfigName: r_appConfig.outputs.appConfigName

    saName: r_sa.outputs.saName
    blobContainerName: r_blob.outputs.blobContainerName

    cosmos_db_accnt_name: r_cosmosdb.outputs.cosmos_db_accnt_name
    cosmos_db_name: r_cosmosdb.outputs.cosmos_db_name
    cosmos_db_container_name: r_cosmosdb.outputs.cosmos_db_container_name

    svc_bus_ns_name: r_svc_bus.outputs.svc_bus_ns_name
    svc_bus_q_name: r_svc_bus.outputs.svc_bus_q_name
    svc_bus_topic_name: r_svc_bus_topic.outputs.svc_bus_topic_name
    sales_events_subscriber_name: r_svc_bus_sub_filter.outputs.sales_events_subscriber_name

  }
  dependsOn: [
    r_sa
    r_logAnalyticsWorkspace
  ]
}

// Create Avaialbility Test
module r_availability_test 'modules/monitor/create_availability_tests.bicep' = {
  name: '${deploymentParams.enterprise_name_suffix}_${deploymentParams.loc_short_code}_${deploymentParams.global_uniqueness}_availability_test'
  params: {
    deploymentParams: deploymentParams
    r_app_insights_name: r_fn_app.outputs.r_app_insights_name
    fn_app_name: r_fn_app.outputs.fn_app_name
  }
}

// Create the Service Bus & Queue
module r_svc_bus 'modules/integration/create_svc_bus.bicep' = {
  // scope: resourceGroup(r_rg.name)
  name: '${svc_bus_params.serviceBusNamePrefix}_${deploymentParams.global_uniqueness}_svc_bus'
  params: {
    deploymentParams: deploymentParams
    svc_bus_params: svc_bus_params
    tags: tags
    logAnalyticsWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId
    enableDiagnostics: true
  }
}

// Create Service Bus Topic
module r_svc_bus_topic 'modules/integration/create_topic.bicep' = {
  name: '${svc_bus_params.serviceBusNamePrefix}_${deploymentParams.global_uniqueness}_svc_bus_topic'
  params: {
    deploymentParams: deploymentParams
    svc_bus_params: svc_bus_params
    svc_bus_ns_name: r_svc_bus.outputs.svc_bus_ns_name
    tags: tags
  }
  dependsOn: [
    r_svc_bus
  ]
}

// Create Service Bus Subscription Filter
module r_svc_bus_sub_filter 'modules/integration/create_queue_subscription.bicep' = {
  name: '${svc_bus_params.serviceBusNamePrefix}_${deploymentParams.global_uniqueness}_svc_bus_sub_filter'
  params: {
    deploymentParams: deploymentParams
    svc_bus_params: svc_bus_params

    svc_bus_ns_name: r_svc_bus.outputs.svc_bus_ns_name
    svc_bus_topic_name: r_svc_bus_topic.outputs.svc_bus_topic_name

  }
  dependsOn: [
    r_svc_bus
    r_svc_bus_topic
  ]
}

// Create Data Collection Endpoint
module r_dataCollectionEndpoint 'modules/monitor/data_collection_endpoint.bicep' = {
  name: '${dceParams.endpointNamePrefix}_${deploymentParams.global_uniqueness}_dce'
  params: {
    deploymentParams: deploymentParams
    dceParams: dceParams
    osKind: 'linux'
    tags: tags
  }
}

// Create the Data Collection Rule
module r_dataCollectionRule 'modules/monitor/data_collection_rule.bicep' = {
  name: '${logAnalyticsWorkspaceParams.name_prefix}_${deploymentParams.global_uniqueness}_dcr'
  params: {
    deploymentParams: deploymentParams
    osKind: 'Linux'
    tags: tags

    storeEventsRuleName: 'storeEvents_Dcr'
    storeEventsLogFilePattern: '/var/log/miztiik*.json'
    storeEventscustomTableNamePrefix: r_logAnalyticsWorkspace.outputs.storeEventsCustomTableNamePrefix

    automationEventsRuleName: 'miztiikAutomation_Dcr'
    automationEventsLogFilePattern: '/var/log/miztiik-automation-*.log'
    automationEventsCustomTableNamePrefix: r_logAnalyticsWorkspace.outputs.automationEventsCustomTableNamePrefix

    managedRunCmdRuleName: 'miztiikManagedRunCmd_Dcr'
    managedRunCmdLogFilePattern: '/var/log/azure/run-command-handler/*.log'
    managedRunCmdCustomTableNamePrefix: r_logAnalyticsWorkspace.outputs.managedRunCmdCustomTableNamePrefix

    linDataCollectionEndpointId: r_dataCollectionEndpoint.outputs.linDataCollectionEndpointId
    logAnalyticsPayGWorkspaceName: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceName
    logAnalyticsPayGWorkspaceId: r_logAnalyticsWorkspace.outputs.logAnalyticsPayGWorkspaceId

  }
  dependsOn: [
    r_logAnalyticsWorkspace
  ]
}

// Create the VNets
module r_vnet 'modules/vnet/create_vnet.bicep' = {
  name: '${vnet_params.vnet_name_prefix}_${deploymentParams.global_uniqueness}_vnet'
  params: {
    deploymentParams: deploymentParams
    vnet_params: vnet_params
    tags: tags
  }
}
