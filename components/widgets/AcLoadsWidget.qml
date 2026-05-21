/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
**
** Ekrano multi-vebus mod: when more than one com.victronenergy.vebus.* service is
** present, the displayed load power is the sum of /Ac/Out/P across every vebus
** service (each /Ac/Out/P already aggregates L1+L2+L3 within its service). This
** is needed because Global.system.load.ac only reflects the single VE.Bus that
** the system-service treats as the main inverter; the others appear only in the
** device list. With <= 1 vebus services we use the stock Global.system.load.*
** sources unchanged, so single-inverter setups are unaffected.
*/

import QtQuick
import QtQuick.Layouts
import Victron.VenusOS

AcWidget {
	id: root

	readonly property bool _multiVebusMode: vebusModel.count > 1

	readonly property real _multiVebusPower: {
		// Re-evaluates whenever any of the instantiated power probes change.
		let total = 0
		let any = false
		for (let i = 0; i < vebusPowerProbes.count; ++i) {
			const probe = vebusPowerProbes.objectAt(i)
			if (!probe) continue
			const v = probe.value
			if (!isNaN(v)) {
				total += v
				any = true
			}
		}
		return any ? total : NaN
	}

	readonly property QtObject _multiVebusMeasurements: QtObject {
		readonly property real power: root._multiVebusPower
		// AcWidgetContent reads `.phases` from quantityDataObject indirectly; keep
		// the same shape as Global.system.load.ac to avoid binding loops, but with
		// a null model so ThreePhaseDisplay collapses to empty.
		readonly property var phases: null
	}

	// The drilldown page (AcLoadListPage) requires a typed ObjectAcConnection, so we
	// always keep _systemMeasurements pointing at the stock object and only override
	// the displayed quantity/phase fields for the tile itself in multi-vebus mode.
	readonly property ObjectAcConnection _systemMeasurements: Global.system.showInputLoads
			? Global.system.load.acIn
			: Global.system.load.ac

	//% "AC Loads"
	title: qsTrId("overview_widget_acloads_title")
	type: VenusOS.OverviewWidget_Type_AcLoads
	quantitySourceType: VenusOS.ElectricalQuantity_Source_Ac
	quantityDataObject: _multiVebusMode ? _multiVebusMeasurements : _systemMeasurements
	phaseModel: _multiVebusMode
			? null
			: (_systemMeasurements.phases.count > 1 || _systemMeasurements.l2AndL1OutSummed
					? _systemMeasurements.phases : null)

	enabled: _multiVebusMode
			? !isNaN(_multiVebusPower)
			: (_systemMeasurements.phaseCount > 1 || acLoadDevices.count > 0)

	FilteredDeviceModel {
		id: vebusModel
		serviceTypes: ["vebus"]
		sorting: FilteredDeviceModel.DeviceInstance
	}

	Instantiator {
		id: vebusPowerProbes

		model: vebusModel
		delegate: VeQuickItem {
			required property Device device
			uid: device.serviceUid + "/Ac/Out/P"
		}
	}

	contentItem: AcWidgetContent {
		widget: root
		iconSource: "qrc:/images/acloads.svg"
		gaugeValueType: VenusOS.Gauges_ValueType_RisingPercentage
		gaugeMaximumValue: Global.system.load.maximumAcCurrent
	}

	onClicked: {
		Global.pageManager.pushPage("/pages/loads/AcLoadListPage.qml", {
			title: root.title,
			measurements: root._systemMeasurements,
			model: acLoadDevices,
		})
	}

	FilteredDeviceModel {
		id: acLoadDevices
		serviceTypes: ["acload", "evcharger", "heatpump"]
		childFilterIds: Global.system.showInputLoads
				? { "acload": ["Position"], "evcharger": ["Position"], "heatpump": ["Position"] }
				: {}
		childFilterFunction: (device, childItems) => {
			const pos = childItems["Position"]
			return !pos || pos.value === undefined || pos.value === VenusOS.AcPosition_AcInput
		}
	 }
}
