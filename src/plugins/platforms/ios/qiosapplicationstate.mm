/****************************************************************************
**
** Copyright (C) 2016 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the plugins of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 3 as published by the Free Software
** Foundation and appearing in the file LICENSE.LGPL3 included in the
** packaging of this file. Please review the following information to
** ensure the GNU Lesser General Public License version 3 requirements
** will be met: https://www.gnu.org/licenses/lgpl-3.0.html.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 2.0 or (at your option) the GNU General
** Public license version 3 or any later version approved by the KDE Free
** Qt Foundation. The licenses are as published by the Free Software
** Foundation and appearing in the file LICENSE.GPL2 and LICENSE.GPL3
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-2.0.html and
** https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/

#include "qiosapplicationstate.h"

#include "qiosglobal.h"
#include "qiosintegration.h"

#include <qpa/qwindowsysteminterface.h>
#include <QtCore/qcoreapplication.h>

#include <QtGui/private/qguiapplication_p.h>

QT_BEGIN_NAMESPACE

static void qRegisterApplicationStateNotifications()
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];

    // Map between notifications and corresponding application state. Note that
    // there's no separate notification for moving to UIApplicationStateInactive,
    // so we use UIApplicationWillResignActiveNotification as an intermediate.
    static QMap<NSNotificationName, UIApplicationState> notifications {
        { UIApplicationWillEnterForegroundNotification, UIApplicationStateInactive },
        { UIApplicationDidBecomeActiveNotification, UIApplicationStateActive },
        { UIApplicationWillResignActiveNotification, UIApplicationStateInactive },
        { UIApplicationDidEnterBackgroundNotification, UIApplicationStateBackground },
    };

    for (auto i = notifications.constBegin(); i != notifications.constEnd(); ++i) {
        [notificationCenter addObserverForName:i.key() object:nil queue:mainQueue
            usingBlock:^void(NSNotification *notification) {
                NSRange nameRange = NSMakeRange(2, notification.name.length - 14);
                QString reason = QString::fromNSString([notification.name substringWithRange:nameRange]);
                QIOSApplicationState::handleApplicationStateChanged(i.value(), reason);
        }];
    }

    // Initialize correct startup state, which may not be the Qt default (inactive)
    UIApplicationState startupState = [UIApplication sharedApplication].applicationState;
    QIOSApplicationState::handleApplicationStateChanged(startupState, QLatin1String("Application loaded"));
}
Q_CONSTRUCTOR_FUNCTION(qRegisterApplicationStateNotifications)

QIOSApplicationState::QIOSApplicationState()
{
    UIApplicationState startupState = [UIApplication sharedApplication].applicationState;
    QIOSApplicationState::handleApplicationStateChanged(startupState, QLatin1String("Application launched"));
}

void QIOSApplicationState::handleApplicationStateChanged(UIApplicationState uiState, const QString &reason)
{
    Qt::ApplicationState state = toQtApplicationState(uiState);
    qCDebug(lcQpaApplication) << qPrintable(reason)
        << "- moving from" << QGuiApplication::applicationState() << "to" << state;

    if (QIOSIntegration *integration = QIOSIntegration::instance()) {
        emit integration->applicationState.applicationStateWillChange(state);
        QWindowSystemInterface::handleApplicationStateChanged(state);
        emit integration->applicationState.applicationStateDidChange(state);
        qCDebug(lcQpaApplication) << "done moving to" << state;
    } else {
        qCDebug(lcQpaApplication) << "no platform integration yet, setting state directly";
        QGuiApplicationPrivate::applicationState = state;
    }
}

Qt::ApplicationState QIOSApplicationState::toQtApplicationState(UIApplicationState state)
{
    switch (state) {
    case UIApplicationStateActive: return Qt::ApplicationActive;
    case UIApplicationStateInactive: return Qt::ApplicationInactive;
    case UIApplicationStateBackground: return Qt::ApplicationSuspended;
    }
}

#include "moc_qiosapplicationstate.cpp"

QT_END_NAMESPACE
