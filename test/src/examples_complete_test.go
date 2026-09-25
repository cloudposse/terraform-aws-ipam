package test

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	testStructure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func cleanup(t *testing.T, terraformOptions *terraform.Options, tempTestFolder string) {
	terraform.Destroy(t, terraformOptions)
	os.RemoveAll(tempTestFolder)
}

// Test the Terraform module in examples/complete using Terratest.
func TestExamplesComplete(t *testing.T) {
	t.Parallel()
	randID := strings.ToLower(random.UniqueId())
	attributes := []string{randID}

	rootFolder := "../../"
	terraformFolderRelativeToRoot := "examples/complete"
	varFiles := []string{"fixtures.us-east-2.tfvars"}

	tempTestFolder := testStructure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		// Variables to pass to our Terraform code using -var-file options
		VarFiles: varFiles,
		Vars: map[string]interface{}{
			"attributes": attributes,
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer cleanup(t, terraformOptions, tempTestFolder)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)

	// The IPAM itself
	ipamID := terraform.Output(t, terraformOptions, "ipam_id")
	assert.True(t, strings.HasPrefix(ipamID, "ipam-"), "Expected an IPAM ID, got %q", ipamID)

	// Creating an IPAM implicitly creates both default scopes. The public one
	// cannot be created any other way, so it must come back non-empty.
	privateScopeID := terraform.Output(t, terraformOptions, "private_default_scope_id")
	publicScopeID := terraform.Output(t, terraformOptions, "public_default_scope_id")
	assert.True(t, strings.HasPrefix(privateScopeID, "ipam-scope-"), "Expected a private default scope ID, got %q", privateScopeID)
	assert.True(t, strings.HasPrefix(publicScopeID, "ipam-scope-"), "Expected a public default scope ID, got %q", publicScopeID)

	// The additional private scope the example asks for
	scopeIDs := terraform.OutputMap(t, terraformOptions, "scope_ids")
	assert.Len(t, scopeIDs, 1, "Expected exactly one additional scope")
	workloadScopeID := scopeIDs["workloads"]
	assert.True(t, strings.HasPrefix(workloadScopeID, "ipam-scope-"), "Expected a scope ID, got %q", workloadScopeID)
	assert.NotEqual(t, privateScopeID, workloadScopeID, "Expected the additional scope to differ from the default one")

	// All four tiers of the hierarchy, keyed by the names the caller supplied
	poolIDs := terraform.OutputMap(t, terraformOptions, "pool_ids")
	assert.Len(t, poolIDs, 4, "Expected one ID per pool across all four depth tiers")
	for _, poolName := range []string{"core", "regional", "env", "app"} {
		assert.Contains(t, poolIDs, poolName, "Expected `pool_ids` to be keyed by the caller's pool name")
		assert.True(t, strings.HasPrefix(poolIDs[poolName], "ipam-pool-"),
			"Expected an IPAM pool ID for %q, got %q", poolName, poolIDs[poolName])
	}

	// Every pool sits in the explicitly named scope: the top-level pool because
	// it names it, the other three because they inherit it from their parent.
	poolScopeIDs := terraform.OutputMap(t, terraformOptions, "pool_scope_ids")
	for _, poolName := range []string{"core", "regional", "env", "app"} {
		assert.Equal(t, workloadScopeID, poolScopeIDs[poolName],
			"Expected pool %q to sit in the named scope, inheriting it from its parent where applicable", poolName)
	}

	// Proves the null-label context reaches the pools, which is what carries the
	// Name tag and the default description for each one.
	poolNames := terraform.OutputMap(t, terraformOptions, "pool_names")
	assert.Equal(t, "eg-ue2-test-example-"+randID+"-core", poolNames["core"])
	assert.Equal(t, "eg-ue2-test-example-"+randID+"-app", poolNames["app"])

	// The top-level pool holds the CIDR the example provisioned verbatim; the
	// children were given netmask lengths, so IPAM chose their blocks.
	var poolCIDRs map[string][]string
	require.NoError(t, json.Unmarshal([]byte(terraform.OutputJson(t, terraformOptions, "pool_cidrs")), &poolCIDRs))
	assert.Equal(t, []string{"10.0.0.0/8"}, poolCIDRs["core"], "Expected the supernet to be provisioned into the top-level pool")
	for _, poolName := range []string{"regional", "env", "app"} {
		assert.Len(t, poolCIDRs[poolName], 1, "Expected exactly one CIDR provisioned into %q", poolName)
	}

	// The manual reservation holds space inside the deepest pool
	allocationCIDRs := terraform.OutputMap(t, terraformOptions, "allocation_cidrs")
	assert.Len(t, allocationCIDRs, 1, "Expected exactly one manual reservation")
	assert.Contains(t, allocationCIDRs, "app/reserved", "Expected the allocation to be keyed `<pool name>/<allocation name>`")
	assert.True(t, strings.HasSuffix(allocationCIDRs["app/reserved"], "/24"),
		"Expected a /24 reservation, got %q", allocationCIDRs["app/reserved"])

	// The explicitly created resource discovery, distinct from the default one
	resourceDiscoveryID := terraform.Output(t, terraformOptions, "resource_discovery_id")
	assert.True(t, strings.HasPrefix(resourceDiscoveryID, "ipam-res-disco-"),
		"Expected a resource discovery ID, got %q", resourceDiscoveryID)

	// A second apply must be a no-op. This matters more than usual here: several
	// pool arguments are read by the provider with `d.GetOk` rather than
	// `d.HasChange`, and the module leans on the provider's own defaults for
	// anything it does not set.
	terraform.Apply(t, terraformOptions)

	poolIDs2 := terraform.OutputMap(t, terraformOptions, "pool_ids")
	assert.Equal(t, poolIDs, poolIDs2, "Expected `pool_ids` to be stable across applies")
}

func TestExamplesCompleteDisabled(t *testing.T) {
	t.Parallel()
	randID := strings.ToLower(random.UniqueId())
	attributes := []string{randID}

	rootFolder := "../../"
	terraformFolderRelativeToRoot := "examples/complete"
	varFiles := []string{"fixtures.us-east-2.tfvars"}

	tempTestFolder := testStructure.CopyTerraformFolderToTemp(t, rootFolder, terraformFolderRelativeToRoot)

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: tempTestFolder,
		Upgrade:      true,
		// Variables to pass to our Terraform code using -var-file options
		VarFiles: varFiles,
		Vars: map[string]interface{}{
			"attributes": attributes,
			"enabled":    "false",
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer cleanup(t, terraformOptions, tempTestFolder)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	results := terraform.InitAndApply(t, terraformOptions)

	// Should complete successfully without creating or changing any resources
	assert.Contains(t, results, "Resources: 0 added, 0 changed, 0 destroyed.")
}
