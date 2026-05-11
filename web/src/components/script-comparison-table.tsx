"use client";

import React from "react";
import { motion } from "framer-motion";
import { Check, X, ArrowRight } from "lucide-react";
import { Button } from "~/components/ui/button";

interface ComparisonRow {
  feature: string;
  operational: string | boolean;
  notification: string | boolean;
}

const comparisonData: ComparisonRow[] = [
  {
    feature: "Execution Environment",
    operational: "Local + Azure Automation",
    notification: "Azure Automation Only",
  },
  {
    feature: "Output Method",
    operational: "Files (CSV, JSON, HTML)",
    notification: "Email Notifications Only",
  },
  {
    feature: "Authentication",
    operational: "Interactive + Managed Identity",
    notification: "Managed Identity Only",
  },
  {
    feature: "Scheduling",
    operational: "Optional",
    notification: "Required (Daily/Weekly)",
  },
  {
    feature: "Primary Use Case",
    operational: "On-demand tasks & reporting",
    notification: "Continuous monitoring & alerting",
  },
  {
    feature: "Parameters",
    operational: "Multiple configuration options",
    notification: "Minimal (threshold + recipients)",
  },
  {
    feature: "User Interaction",
    operational: "Direct execution & immediate results",
    notification: "Set-and-forget automation",
  },
  {
    feature: "Microsoft Graph Permissions",
    operational: "Read-only for specific resources",
    notification: "Read + Mail.Send",
  },
  {
    feature: "Local Execution Support",
    operational: true,
    notification: false,
  },
  {
    feature: "Email Alerts",
    operational: false,
    notification: true,
  },
];

export function ScriptComparisonTable() {
  return (
    <section className="py-16">
      <div className="container mx-auto px-4">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
          className="mx-auto max-w-5xl"
        >
          <h2 className="mb-4 text-center text-3xl font-bold">
            Script Types Comparison
          </h2>
          <p className="text-muted-foreground mb-12 text-center text-lg">
            Understanding the differences between script types helps you choose
            the right tool for your needs.
          </p>

          {/* Desktop Table */}
          <div className="hidden overflow-hidden rounded-xl border shadow-sm md:block">
            <table className="w-full">
              <thead>
                <tr className="bg-muted/50 border-b">
                  <th className="p-4 text-left font-semibold">Feature</th>
                  <th className="p-4 text-left">
                    <div className="flex items-center gap-2">
                      <span className="text-lg">⚙️</span>
                      <div>
                        <div className="font-semibold">
                          Operational & Reporting Scripts
                        </div>
                        <div className="text-muted-foreground text-sm font-normal">
                          Traditional scripts
                        </div>
                      </div>
                    </div>
                  </th>
                  <th className="p-4 text-left">
                    <div className="flex items-center gap-2">
                      <span className="text-lg">🔔</span>
                      <div>
                        <div className="flex items-center gap-2 font-semibold">
                          Notification Scripts
                          <span className="rounded bg-red-500 px-1.5 py-0.5 text-xs font-medium text-white">
                            NEW
                          </span>
                        </div>
                        <div className="text-muted-foreground text-sm font-normal">
                          Monitoring & alerts
                        </div>
                      </div>
                    </div>
                  </th>
                </tr>
              </thead>
              <tbody>
                {comparisonData.map((row, index) => (
                  <motion.tr
                    key={index}
                    initial={{ opacity: 0, x: -20 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: index * 0.05 }}
                    className="hover:bg-muted/30 border-b transition-colors"
                  >
                    <td className="p-4 font-medium">{row.feature}</td>
                    <td className="p-4">
                      {typeof row.operational === "boolean" ? (
                        row.operational ? (
                          <Check className="h-5 w-5 text-green-600" />
                        ) : (
                          <X className="h-5 w-5 text-red-600" />
                        )
                      ) : (
                        <span className="text-muted-foreground">
                          {row.operational}
                        </span>
                      )}
                    </td>
                    <td className="p-4">
                      {typeof row.notification === "boolean" ? (
                        row.notification ? (
                          <Check className="h-5 w-5 text-green-600" />
                        ) : (
                          <X className="h-5 w-5 text-red-600" />
                        )
                      ) : (
                        <span className="text-muted-foreground">
                          {row.notification}
                        </span>
                      )}
                    </td>
                  </motion.tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Mobile Cards */}
          <div className="space-y-4 md:hidden">
            {comparisonData.map((row, index) => (
              <motion.div
                key={index}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.05 }}
                className="bg-card rounded-lg border p-4"
              >
                <h4 className="mb-3 font-semibold">{row.feature}</h4>
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-muted-foreground text-sm">
                      Operational/Reporting
                    </span>
                    {typeof row.operational === "boolean" ? (
                      row.operational ? (
                        <Check className="h-4 w-4 text-green-600" />
                      ) : (
                        <X className="h-4 w-4 text-red-600" />
                      )
                    ) : (
                      <span className="text-sm">{row.operational}</span>
                    )}
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-muted-foreground text-sm">
                      Notification
                    </span>
                    {typeof row.notification === "boolean" ? (
                      row.notification ? (
                        <Check className="h-4 w-4 text-green-600" />
                      ) : (
                        <X className="h-4 w-4 text-red-600" />
                      )
                    ) : (
                      <span className="text-sm">{row.notification}</span>
                    )}
                  </div>
                </div>
              </motion.div>
            ))}
          </div>

          {/* Summary Cards */}
          <div className="mt-12 grid gap-6 md:grid-cols-2">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.6 }}
              className="bg-card rounded-xl border p-6"
            >
              <h3 className="mb-4 text-xl font-semibold">
                When to Use Operational/Reporting Scripts
              </h3>
              <ul className="space-y-2">
                <li className="flex items-start gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
                  <span className="text-muted-foreground">
                    Need immediate results or reports
                  </span>
                </li>
                <li className="flex items-start gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
                  <span className="text-muted-foreground">
                    Running ad-hoc analysis or troubleshooting
                  </span>
                </li>
                <li className="flex items-start gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
                  <span className="text-muted-foreground">
                    Exporting data for further processing
                  </span>
                </li>
                <li className="flex items-start gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
                  <span className="text-muted-foreground">
                    Performing one-time administrative tasks
                  </span>
                </li>
              </ul>
            </motion.div>

            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.7 }}
              className="rounded-xl border border-violet-200 bg-gradient-to-br from-violet-50/50 to-indigo-50/50 p-6 dark:border-violet-800 dark:from-violet-950/20 dark:to-indigo-950/20"
            >
              <h3 className="mb-4 text-xl font-semibold">
                When to Use Notification Scripts
              </h3>
              <ul className="mb-6 space-y-2">
                <li className="flex items-start gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
                  <span className="text-muted-foreground">
                    Want proactive monitoring of your environment
                  </span>
                </li>
                <li className="flex items-start gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
                  <span className="text-muted-foreground">
                    Need alerts for critical events or thresholds
                  </span>
                </li>
                <li className="flex items-start gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
                  <span className="text-muted-foreground">
                    Managing compliance and security posture
                  </span>
                </li>
                <li className="flex items-start gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
                  <span className="text-muted-foreground">
                    Tracking expiration dates and renewals
                  </span>
                </li>
              </ul>
              <Button
                variant="outline"
                className="w-full justify-between border-violet-300 hover:bg-violet-100 dark:border-violet-700 dark:hover:bg-violet-900/50"
                onClick={() => {
                  const scriptsSection =
                    document.getElementById("scripts-section");
                  if (scriptsSection) {
                    scriptsSection.scrollIntoView({ behavior: "smooth" });
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
                <span>Explore Notification Scripts</span>
                <ArrowRight className="h-4 w-4" />
              </Button>
            </motion.div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}
