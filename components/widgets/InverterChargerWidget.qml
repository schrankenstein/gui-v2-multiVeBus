/*
** Copyright (C) 2023 Victron Energy B.V.
** See LICENSE.txt for license information.
**
** Ekrano multi-vebus mod: when more than one com.victronenergy.vebus.* service is
** present, the widget renders one mini-tile per VE.Bus service side-by-side instead
** of a single state/load summary. Services are shown in DeviceInstance order, so the
** internal VE.Bus (which is the grid-connected one and gets the lowest instance on
** the Ekrano GX) ends up leftmost. With <= 1 vebus services the widget renders
** identically to the original Victron implementation.
*/

import QtQuick
import QtQuick.Layouts
import Victron.VenusOS

OverviewWidget {
	id: root

	readonly property int vebusServiceCount: vebusModel.count
	readonly property bool multiVebusMode: vebusServiceCount > 1

	onClicked: {
		if (Global.inverterChargers.deviceCount > 1) {
			Global.pageManager.pushPage("/pages/invertercharger/InverterChargerListPage.qml")
		} else {
			chargerModelLoader.active = true
			if (chargerModelLoader.item.count > 0) {
				const charger = chargerModelLoader.item.firstObject
				Global.pageManager.pushPage("/pages/settings/devicelist/PageAcCharger.qml",
						{ "bindPrefix": charger.serviceUid })
			} else {
				const device = Global.inverterChargers.firstObject
				Global.pageManager.pushPage("/pages/invertercharger/OverviewInverterChargerPage.qml",
						{ "serviceUid": device.serviceUid })
			}
		}
	}

	//% "Inverter / Charger"
	title: qsTrId("overview_widget_inverter_title")
	type: VenusOS.OverviewWidget_Type_VeBusDevice
	enabled: !!Global.inverterChargers.firstObject
	rightPadding: multiVebusMode ? Theme.geometry_overviewPage_widget_content_horizontalMargin
								 : Theme.geometry_overviewPage_widget_sideGauge_margins

	FilteredDeviceModel {
		id: vebusModel
		serviceTypes: ["vebus"]
		sorting: FilteredDeviceModel.DeviceInstance
	}

	contentItem: Loader {
		sourceComponent: root.multiVebusMode ? multiVebusContent : singleVebusContent
	}

	Component {
		id: singleVebusContent

		Item {
			implicitWidth: Theme.geometry_overviewPage_widget_centerWidgetWidth
			implicitHeight: singleContentLayout.implicitHeight

			ColumnLayout {
				id: singleContentLayout

				width: parent.width - sideGaugeLoader.width - Theme.geometry_overviewPage_widget_sideGauge_margins
				height: parent.height
				spacing: Theme.geometry_overviewPage_widget_content_spacing

				WidgetHeader {
					text: root.title
					icon.source: "qrc:/images/inverter_charger.svg"
					Layout.fillWidth: true
				}

				Label {
					text: VenusOS.system_stateToText(Global.system.state)
					font.pixelSize: Theme.font_overviewPage_widget_quantityLabel_maximumSize
					minimumPixelSize: Theme.font_overviewPage_widget_quantityLabel_minimumSize
					fontSizeMode: Text.Fit
					wrapMode: Text.WordWrap
					maximumLineCount: 4
					elide: Text.ElideRight

					Layout.fillWidth: true
					Layout.fillHeight: true
				}

				Label {
					text: systemReason.text
					wrapMode: Text.WordWrap
					color: Theme.color_font_secondary
					font.pixelSize: root.secondaryFontSize

					SystemReason {
						id: systemReason
					}
				}
			}

			Loader {
				id: sideGaugeLoader

				anchors {
					top: parent.top
					bottom: parent.bottom
					right: parent.right
				}
				sourceComponent: ThreePhaseBarGauge {
					valueType: VenusOS.Gauges_ValueType_RisingPercentage
					phaseModel: Global.system.load.ac.phases
					maximumValue: Global.system.load.maximumAcCurrent
					animationEnabled: root.animationEnabled
					inOverviewWidget: true
				}
			}
		}
	}

	Component {
		id: multiVebusContent

		Item {
			implicitWidth: Theme.geometry_overviewPage_widget_centerWidgetWidth
			implicitHeight: multiContentLayout.implicitHeight

			ColumnLayout {
				id: multiContentLayout

				anchors.fill: parent
				spacing: Theme.geometry_overviewPage_widget_content_spacing

				WidgetHeader {
					text: root.title
					icon.source: "qrc:/images/inverter_charger.svg"
					Layout.fillWidth: true
				}

				RowLayout {
					Layout.fillWidth: true
					Layout.fillHeight: true
					spacing: Theme.geometry_overviewPage_widget_spacing

					Repeater {
						model: vebusModel

						delegate: Rectangle {
							id: miniTile

							required property Device device

							Layout.fillWidth: true
							Layout.fillHeight: true

							color: "transparent"
							border.width: Theme.geometry_overviewPage_widget_border_width
							border.color: Theme.color_overviewPage_widget_border
							radius: Theme.geometry_overviewPage_widget_radius

							VeQuickItem {
								id: stateItem
								uid: miniTile.device.serviceUid + "/State"
							}

							VeQuickItem {
								id: powerItem
								uid: miniTile.device.serviceUid + "/Ac/Out/P"
							}

							VeQuickItem {
								id: connectedItem
								uid: miniTile.device.serviceUid + "/Ac/ActiveIn/Connected"
							}

							ColumnLayout {
								anchors.fill: parent
								anchors.margins: Theme.geometry_overviewPage_widget_content_spacing
								spacing: 2

								Label {
									Layout.fillWidth: true
									text: miniTile.device.name || "VE.Bus"
									font.pixelSize: root.secondaryFontSize
									font.bold: connectedItem.value === 1
									elide: Text.ElideRight
									maximumLineCount: 1
								}

								Label {
									Layout.fillWidth: true
									Layout.fillHeight: true
									text: VenusOS.system_stateToText(stateItem.value)
									font.pixelSize: root.secondaryFontSize
									wrapMode: Text.WordWrap
									elide: Text.ElideRight
									maximumLineCount: 2
									color: Theme.color_font_secondary
								}

								Label {
									Layout.fillWidth: true
									text: isNaN(powerItem.value) ? "—"
											: Math.round(powerItem.value) + " W"
									font.pixelSize: root.tertiaryFontSize
									color: Theme.color_font_primary
									elide: Text.ElideRight
								}
							}

							MouseArea {
								anchors.fill: parent
								onClicked: {
									Global.pageManager.pushPage(
										"/pages/invertercharger/OverviewInverterChargerPage.qml",
										{ "serviceUid": miniTile.device.serviceUid })
								}
							}
						}
					}
				}
			}
		}
	}

	Loader {
		id: chargerModelLoader
		active: false
		sourceComponent: FilteredDeviceModel {
			serviceTypes: ["charger"]
			sorting: FilteredDeviceModel.DeviceInstance
		}
	}
}
