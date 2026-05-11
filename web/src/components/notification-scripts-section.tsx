"use client";

import React from "react";
import Link from "next/link";
import { motion } from "framer-motion";
import { Badge } from "~/components/ui/badge";
import { Button } from "~/components/ui/button";
import {
  Bell,
  Mail,
  Calendar,
  Shield,
  AlertTriangle,
  Package,
  Smartphone,
  ArrowRight,
  CloudLightning,
  Clock,
  CheckCircle,
} from "lucide-react";

const features = [
  {
    icon: "🍎",
    lucideIcon: Smartphone,
    title: "Apple Token Monitoring",
    description: "Get alerts before DEP tokens and APNS certificates expire",
    script: "apple-token-expiration-alert",
    benefits: [
      "Prevent enrollment failures",
      "Plan renewals in advance",
      "Multiple threshold options",
    ],
    color: "text-blue-600 bg-blue-50 dark:text-blue-400 dark:bg-blue-950/50",
  },
  {
    icon: "📱",
    lucideIcon: Smartphone,
    title: "Stale Device Detection",
    description: "Identify devices that haven't checked in for cleanup",
    script: "stale-device-cleanup-alert",
    benefits: [
      "Optimize licensing costs",
      "Maintain clean inventory",
      "Platform-specific analysis",
    ],
    color:
      "text-green-600 bg-green-50 dark:text-green-400 dark:bg-green-950/50",
  },
  {
    icon: "🛡️",
    lucideIcon: Shield,
    title: "Compliance Drift Alerts",
    description: "Monitor when devices fall out of compliance",
    script: "device-compliance-drift-alert",
    benefits: [
      "Maintain security posture",
      "Track compliance trends",
      "Policy-specific insights",
    ],
    color:
      "text-orange-600 bg-orange-50 dark:text-orange-400 dark:bg-orange-950/50",
  },
  {
    icon: "📦",
    lucideIcon: Package,
    title: "App Deployment Monitoring",
    description: "Track application deployment failures and issues",
    script: "app-deployment-failure-alert",
    benefits: [
      "Ensure app availability",
      "Identify problem apps",
      "Platform-specific metrics",
    ],
    color:
      "text-purple-600 bg-purple-50 dark:text-purple-400 dark:bg-purple-950/50",
  },
];

const setupSteps = [
  {
    number: "1",
    title: "Deploy to Azure",
    description: "Use our templates to deploy scripts to Azure Automation",
    icon: CloudLightning,
  },
  {
    number: "2",
    title: "Configure Thresholds",
    description: "Set monitoring thresholds that match your requirements",
    icon: AlertTriangle,
  },
  {
    number: "3",
    title: "Add Recipients",
    description: "Specify email addresses for notification delivery",
    icon: Mail,
  },
  {
    number: "4",
    title: "Schedule & Relax",
    description: "Scripts run automatically and alert when needed",
    icon: Calendar,
  },
];

export function NotificationScriptsSection() {
  return (
    <section className="relative overflow-hidden py-24">
      {/* Background gradient */}
      <div className="absolute inset-0 bg-gradient-to-b from-violet-50/50 to-transparent dark:from-violet-950/20" />

      <div className="relative container mx-auto px-4">
        {/* Hero Section */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          className="mx-auto max-w-3xl text-center"
        >
          <Badge className="mb-4 bg-red-500 text-white">NEW</Badge>
          <h2 className="mb-4 text-4xl font-bold">
            <span className="bg-gradient-to-r from-violet-600 to-indigo-600 bg-clip-text text-transparent">
              Proactive Monitoring & Email Alerts
            </span>
          </h2>
          <p className="text-muted-foreground mb-8 text-lg">
            Stay ahead of issues with automated monitoring scripts that send
            email notifications when your Intune environment needs attention.
          </p>

          <div className="mb-12 flex flex-wrap justify-center gap-3">
            <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
              <CloudLightning className="h-3.5 w-3.5" />
              Azure Automation
            </Badge>
            <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
              <Mail className="h-3.5 w-3.5" />
              Email Notifications
            </Badge>
            <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
              <Calendar className="h-3.5 w-3.5" />
              Scheduled Monitoring
            </Badge>
            <Badge variant="outline" className="gap-1.5 px-3 py-1.5">
              <AlertTriangle className="h-3.5 w-3.5" />
              Threshold-Based Alerts
            </Badge>
          </div>
        </motion.div>

        {/* Features Grid */}
        <div className="mb-20">
          <motion.h3
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.2 }}
            className="mb-12 text-center text-2xl font-semibold"
          >
            Available Notification Scripts
          </motion.h3>

          <div className="grid gap-6 md:grid-cols-2">
            {features.map((feature, index) => (
              <motion.div
                key={index}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.1 * index + 0.3 }}
                className="group bg-card relative overflow-hidden rounded-xl border p-6 shadow-sm transition-all duration-300 hover:shadow-lg"
              >
                <div className="absolute inset-0 bg-gradient-to-br from-violet-500/5 to-indigo-500/5 opacity-0 transition-opacity duration-300 group-hover:opacity-100" />

                <div className="relative z-10">
                  <div className="mb-4 flex items-start justify-between">
                    <div className={`rounded-lg p-3 ${feature.color}`}>
                      <span className="text-2xl">{feature.icon}</span>
                    </div>
                    <ArrowRight className="text-muted-foreground/50 group-hover:text-primary h-5 w-5 transition-all duration-300 group-hover:translate-x-1" />
                  </div>

                  <h4 className="mb-2 text-xl font-semibold">
                    {feature.title}
                  </h4>
                  <p className="text-muted-foreground mb-4">
                    {feature.description}
                  </p>

                  <ul className="mb-4 space-y-1.5">
                    {feature.benefits.map((benefit, idx) => (
                      <li key={idx} className="flex items-start gap-2 text-sm">
                        <CheckCircle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-green-600 dark:text-green-400" />
                        <span className="text-muted-foreground">{benefit}</span>
                      </li>
                    ))}
                  </ul>

                  <Link
                    href={`/script/${feature.script}`}
                    className="text-primary hover:text-primary/80 inline-flex items-center gap-1 text-sm font-medium transition-colors"
                  >
                    Learn more
                    <ArrowRight className="h-3.5 w-3.5" />
                  </Link>
                </div>
              </motion.div>
            ))}
          </div>
        </div>

        {/* How It Works */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.6 }}
          className="mb-20"
        >
          <h3 className="mb-4 text-center text-2xl font-semibold">
            How It Works
          </h3>
          <p className="text-muted-foreground mb-12 text-center">
            Get started with proactive monitoring in just a few steps
          </p>

          <div className="grid gap-8 md:grid-cols-4">
            {setupSteps.map((step, index) => {
              const Icon = step.icon;
              return (
                <motion.div
                  key={index}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.1 * index + 0.7 }}
                  className="relative text-center"
                >
                  {index < setupSteps.length - 1 && (
                    <div className="via-border absolute top-12 left-1/2 hidden h-px w-full -translate-x-1/2 bg-gradient-to-r from-transparent to-transparent md:block" />
                  )}

                  <div className="mb-4 inline-flex h-12 w-12 items-center justify-center rounded-full bg-violet-100 text-violet-600 dark:bg-violet-950/50 dark:text-violet-400">
                    <Icon className="h-6 w-6" />
                  </div>

                  <h4 className="mb-2 font-semibold">{step.title}</h4>
                  <p className="text-muted-foreground text-sm">
                    {step.description}
                  </p>
                </motion.div>
              );
            })}
          </div>
        </motion.div>

        {/* CTA Section */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.8 }}
          className="mx-auto max-w-2xl rounded-xl bg-gradient-to-r from-violet-600 to-indigo-600 p-8 text-center text-white"
        >
          <Bell className="mx-auto mb-4 h-12 w-12" />
          <h3 className="mb-2 text-2xl font-bold">
            Ready to Enable Proactive Monitoring?
          </h3>
          <p className="mb-6 text-white/90">
            Choose a script to get started with automated notifications
          </p>
          <div className="flex flex-col gap-3 sm:flex-row sm:justify-center">
            <Button
              size="lg"
              variant="secondary"
              className="bg-white text-violet-600 hover:bg-white/90"
              onClick={() => {
                const scriptsSection =
                  document.getElementById("scripts-section");
                if (scriptsSection) {
                  scriptsSection.scrollIntoView({ behavior: "smooth" });
                  // Trigger notification filter after scrolling
                  setTimeout(() => {
                    const notificationButton = document.querySelector(
                      '[data-tag="Notification"]',
                    );
                    if (notificationButton instanceof HTMLElement) {
                      notificationButton.click();
                    }
                  }, 500);
                }
              }}
            >
              Browse Notification Scripts
            </Button>
            <Button
              asChild
              size="lg"
              variant="outline"
              className="border-white bg-transparent text-white hover:bg-white/10"
            >
              <a
                href="https://github.com/ugurkocde/intuneautomation/tree/main/scripts/notification"
                target="_blank"
                rel="noopener noreferrer"
              >
                View Documentation
              </a>
            </Button>
          </div>
        </motion.div>

        {/* Info Box */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1 }}
          className="mx-auto mt-12 max-w-3xl rounded-lg border border-amber-200 bg-amber-50 p-6 dark:border-amber-800 dark:bg-amber-950/50"
        >
          <div className="flex gap-3">
            <AlertTriangle className="h-5 w-5 shrink-0 text-amber-600 dark:text-amber-400" />
            <div className="space-y-2">
              <h4 className="font-semibold text-amber-900 dark:text-amber-100">
                Important Notes
              </h4>
              <ul className="space-y-1 text-sm text-amber-800 dark:text-amber-200">
                <li>
                  • All notification scripts require Azure Automation with
                  Managed Identity
                </li>
                <li>
                  • Email notifications are sent via Microsoft Graph Mail API
                </li>
                <li>
                  • Scripts include comprehensive error handling and logging
                </li>
                <li>• Thresholds and schedules are fully customizable</li>
              </ul>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}
