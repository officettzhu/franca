/*******************************************************************************
 * Copyright (c) 2016 itemis AG (http://www.itemis.de).
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *******************************************************************************/
package org.franca.connectors.protobuf

import com.google.eclipse.protobuf.ProtobufStandaloneSetup
import com.google.eclipse.protobuf.protobuf.Import
import com.google.eclipse.protobuf.protobuf.Protobuf
import com.google.inject.Guice
import com.google.inject.Injector
import java.util.ArrayList
import java.util.List
import java.util.Map
import java.util.Set
import org.eclipse.emf.common.util.URI
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.resource.XtextResource
import org.eclipse.xtext.resource.XtextResourceSet
import org.franca.core.dsl.FrancaPersistenceManager
import org.franca.core.framework.FrancaModelContainer
import org.franca.core.framework.IFrancaConnector
import org.franca.core.framework.IModelContainer
import org.franca.core.framework.IssueReporter
import org.franca.core.framework.TransformationIssue
import org.franca.core.franca.FModel
import org.franca.core.franca.FType
import org.franca.core.utils.FileHelper
import org.franca.core.utils.digraph.Digraph

public class ProtobufConnector implements IFrancaConnector {

	var Injector injector

	//	private String fileExtension = "proto";
	
	var Set<TransformationIssue> lastTransformationIssues = null

	/** constructor */
	new() {
		injector = Guice.createInjector(new ProtobufConnectorModule())
	}

	override IModelContainer loadModel(String filename) {
		val Map<Protobuf, String> units = loadProtobufModel(filename);
		if (units.isEmpty()) {
			System.out.println("Error: Could not load Protobuf model from file " + filename);
		} else {
			System.out.println("Loaded Protobuf model from file " + filename + " (consists of " + units.size() + " files)");
		}
//		for(Protobuf unit : units.keySet()) {
//			System.out.println("loadModel: " + unit.eResource().getURI() + " is " + units.get(unit));
//		}
		return new ProtobufModelContainer(units);
	}

	override boolean saveModel(IModelContainer model, String filename) {
		if (! (model instanceof ProtobufModelContainer)) {
			return false;
		}

		throw new RuntimeException("saveModel method not implemented yet");

	//		ProtobufModelContainer mc = (ProtobufModelContainer) model;
	//		return saveProtobufModel(createConfiguredResourceSet(), mc.model(), mc.getComments(), fn);
	}

	/**
	 * Convert a Protobuf model to Franca.</p>
	 * 
	 * The input model might consist of multiple files. The output might consist of multiple files, too.</p>
	 * 
	 * @param model the input Protobuf model
	 * @return a model container with the resulting root Franca model and some additional information
	 */
	override FrancaModelContainer toFranca(IModelContainer model) {
		if (! (model instanceof ProtobufModelContainer)) {
			return null;
		}

		val Protobuf2FrancaTransformation trafo = injector.getInstance(Protobuf2FrancaTransformation)
		val ProtobufModelContainer proto = model as ProtobufModelContainer
		val Map<String, EObject> importedModels = newLinkedHashMap

		var Map<EObject, FType> externalTypes = newHashMap
		lastTransformationIssues = newLinkedHashSet
		val inputModels = ListExtensions.reverseView(proto.models)
		var FModel rootModel = null
		var String rootName = null;
		for(item : inputModels) {
			val fmodel = trafo.transform(item, externalTypes)
			externalTypes = trafo.getExternalTypes
			lastTransformationIssues.addAll(trafo.getTransformationIssues)

			if (inputModels.indexOf(item) == inputModels.size-1) {
				// this is the last input model, i.e., the top-most one
				rootModel = fmodel;
				rootName = proto.getFilename(item)
			} else {
				val String importURI =
						proto.getFilename(item) + "." + FrancaPersistenceManager.FRANCA_FILE_EXTENSION;
				importedModels.put(importURI, fmodel)
			}
		}
		
		println(IssueReporter.getReportString(lastTransformationIssues))

		return new FrancaModelContainer(rootModel, rootName, importedModels)
	}


	def CharSequence generateFrancaDeployment(IModelContainer model, String specification, String fidlPath,
		String fileName) {
		if (! (model instanceof ProtobufModelContainer)) {
			return null;
		}

		val Protobuf2FrancaDeploymentGenerator trafo = injector.getInstance(Protobuf2FrancaDeploymentGenerator);
		val ProtobufModelContainer dbus = model as ProtobufModelContainer;
		return trafo.generate(dbus.model(), specification, fidlPath, fileName);
	}

	override IModelContainer fromFranca(FModel fmodel) {

		// ranged integer conversion from Franca to D-Bus as a preprocessing step
		//		IntegerTypeConverter.removeRangedIntegers(fmodel, true);
		// do the actual transformation
		throw new RuntimeException("Franca to Google Protobuf transformation is not yet implemented");
	}

	def Set<TransformationIssue> getLastTransformationIssues() {
		return lastTransformationIssues;
	}

	//	private ResourceSet createConfiguredResourceSet() {
	//		// create new resource set
	//		ResourceSet resourceSet = new ResourceSetImpl();
	//		
	//		// register the appropriate resource factory to handle all file extensions for Google Protobuf
	//		resourceSet.getResourceFactoryRegistry().getExtensionToFactoryMap().put("xml", new ProtobufResourceFactoryImpl());
	//		resourceSet.getPackageRegistry().put(ProtobufPackage.eNS_URI, ProtobufPackage.eINSTANCE);
	//		
	//		return resourceSet;
	//	}
	
	val Map<Protobuf, String> part2import = newLinkedHashMap
	
	def private Map<Protobuf, String> loadProtobufModel(String fileName) {
		
		// we are using a member table to collect the importURI string for all resources
		// TODO: this is clumsy, improve
		part2import.clear
		
		val URI uri = FileHelper.createURI(fileName)

		val injector = new ProtobufStandaloneSetup().createInjectorAndDoEMFRegistration
		val XtextResourceSet resourceSet = injector.getInstance(XtextResourceSet)
		resourceSet.addLoadOption(XtextResource.OPTION_RESOLVE_ALL, Boolean.TRUE)
		val Resource resource = resourceSet.getResource(uri, true)

		if (resource.getContents().isEmpty())
			return null;

		val root = resource.getContents().get(0) as Protobuf
		part2import.put(root, uri.lastSegment.trimExtension(uri.fileExtension))

		val modelURIs = root.collectImportURIsAndLoadModels(uri, resourceSet)
		if (modelURIs.empty) {
			return #[ root ].convert(part2import)
		}

		val digraph = new Digraph => [
			modelURIs.forEach [ p1, p2 |
				p2.forEach [ importUri |
					addEdge(p1, importUri.toString)
				]
			]
		]
		val topoModels = digraph.topoSort
		val models = topoModels.map[resourceSet.getResource(URI.createURI(it), false)?.contents?.head as Protobuf]
		models.convert(part2import)
	}

	def private convert(List<Protobuf> models, Map<Protobuf,String> part2import) {
		val result = models.toInvertedMap[part2import.get(it)]
		result
	}

	def private Map<String, ArrayList<URI>> collectImportURIsAndLoadModels(
		Protobuf model,
		URI importingURI,
		XtextResourceSet resourceSet
	) {
		//val baseURI = importingURI.trimSegments(1)
		val modelURIs = newHashMap
		for(import_ : model.elements.filter(Import)) {
			val importURI = URI.createURI(import_.importURI)
			val resolvedImportURI = importURI.deresolve(importingURI)

			// TODO cycle detection
			val key = model.eResource.URI.toString
			var list = modelURIs.get(key)
			if (list == null) {
				list = <URI>newArrayList
				modelURIs.put(key, list)
			}
			list.add(importURI)
			val importResource = resourceSet.getResource(importURI, false)
			if (! importResource?.contents.empty) {
				val pmodel = importResource.contents.head as Protobuf
				val trimmed = resolvedImportURI.toFileString.trimExtension(importingURI.fileExtension)
				part2import.put(pmodel, trimmed)
				modelURIs.putAll(pmodel.collectImportURIsAndLoadModels(importURI, resourceSet))
			}
		}
		return modelURIs
	}
	
	def private trimExtension(String filename, String ext) {
		val dotIndex = filename.indexOf(ext) - 1
		filename.substring(0, dotIndex)
	}
}
