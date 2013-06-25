package org.franca.core.dsl.validation.internal.util;

import java.util.Collections;
import java.util.List;
import java.util.Set;

import org.eclipse.core.runtime.Assert;
import org.franca.core.franca.FContract;
import org.franca.core.franca.FState;
import org.franca.core.franca.FTransition;

import com.google.common.collect.Lists;
import com.google.common.collect.Sets;

public class FrancaContractDirectedGraphDataSource implements IGraphDataSource<FState> {

	private static final long serialVersionUID = -3071957991109351951L;
	protected FContract contract;
	
	public FrancaContractDirectedGraphDataSource(FContract contract) {
		Assert.isNotNull(contract);
		this.contract = contract;
	}
	
	@Override
	public Set<FState> getAllNodes() {
		return Collections.unmodifiableSet(Sets.newHashSet(contract.getStateGraph().getStates()));
	}

	@Override
	public List<FState> getTargetNodes(FState source) {
		List<FState> targets = Lists.newArrayList();
		for (FTransition t : source.getTransitions()) {
			targets.add(t.getTo());
		}
		return Collections.unmodifiableList(targets);
	}


}
