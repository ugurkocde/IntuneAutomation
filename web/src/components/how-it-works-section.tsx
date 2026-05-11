"use client";

import { motion, useReducedMotion } from "framer-motion";
import { Search, Copy, Zap } from "lucide-react";

const steps = [
  {
    number: "1",
    icon: Search,
    title: "Browse & Search",
    description: "Find the perfect script for your needs",
    color: "from-blue-500 to-blue-600",
    bgColor: "bg-blue-50 dark:bg-blue-950/30",
    iconColor: "text-blue-600 dark:text-blue-400",
  },
  {
    number: "2",
    icon: Copy,
    title: "Copy or Deploy",
    description: "One-click copy or deploy to Azure Automation",
    color: "from-purple-500 to-purple-600",
    bgColor: "bg-purple-50 dark:bg-purple-950/30",
    iconColor: "text-purple-600 dark:text-purple-400",
  },
  {
    number: "3",
    icon: Zap,
    title: "Automate",
    description: "Run manually or schedule for recurring tasks",
    color: "from-green-500 to-green-600",
    bgColor: "bg-green-50 dark:bg-green-950/30",
    iconColor: "text-green-600 dark:text-green-400",
  },
];

export default function HowItWorksSection() {
  const prefersReducedMotion = useReducedMotion();

  return (
    <section className="relative overflow-hidden py-12 sm:py-16 md:py-20">
      {/* Background Elements */}
      <div className="absolute inset-0 z-0" aria-hidden="true">
        <div className="from-background/50 via-background/80 to-background absolute inset-0 bg-gradient-to-b"></div>
      </div>

      <div className="container relative z-10 mx-auto max-w-7xl px-4">
        {/* Section Header */}
        <motion.div
          className="mb-8 text-center sm:mb-10 md:mb-12"
          initial={{ opacity: 0, y: prefersReducedMotion ? 0 : 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
        >
          <h2 className="mb-3 text-2xl font-bold sm:text-3xl md:text-4xl">
            How It Works
          </h2>
          <p className="text-muted-foreground mx-auto max-w-2xl text-base sm:text-lg">
            Get started with Intune automation in three simple steps
          </p>
        </motion.div>

        {/* Steps Grid */}
        <div className="grid grid-cols-1 gap-6 sm:gap-8 md:grid-cols-3">
          {steps.map((step, index) => {
            const IconComponent = step.icon;
            return (
              <motion.div
                key={step.number}
                className="group relative"
                initial={
                  prefersReducedMotion
                    ? { opacity: 1, y: 0 }
                    : { opacity: 0, y: 30 }
                }
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.1 * index, duration: 0.5 }}
                whileHover={
                  prefersReducedMotion
                    ? {}
                    : { y: -8, transition: { duration: 0.2 } }
                }
              >
                {/* Card */}
                <div className="bg-card relative flex h-full flex-col items-center rounded-2xl border p-6 text-center shadow-sm transition-all duration-300 hover:shadow-lg sm:p-8">
                  {/* Step Number Badge */}
                  <div
                    className={`absolute -top-4 left-1/2 flex h-8 w-8 -translate-x-1/2 items-center justify-center rounded-full bg-gradient-to-br ${step.color} text-sm font-bold text-white shadow-lg`}
                  >
                    {step.number}
                  </div>

                  {/* Icon */}
                  <div
                    className={`mb-4 rounded-2xl p-3 transition-all duration-300 group-hover:scale-110 sm:p-4 ${step.bgColor}`}
                  >
                    <IconComponent className={`h-7 w-7 sm:h-8 sm:w-8 ${step.iconColor}`} />
                  </div>

                  {/* Title */}
                  <h3 className="mb-2 text-lg font-bold sm:text-xl">{step.title}</h3>

                  {/* Description */}
                  <p className="text-muted-foreground text-sm leading-relaxed">
                    {step.description}
                  </p>

                  {/* Hover glow effect */}
                  <div
                    className={`absolute -inset-1 -z-10 rounded-2xl bg-gradient-to-br ${step.color} opacity-0 blur-xl transition-opacity duration-300 group-hover:opacity-20`}
                  />
                </div>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}